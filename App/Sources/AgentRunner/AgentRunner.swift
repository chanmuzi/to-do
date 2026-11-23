import Foundation
import Store

public struct AgentResult: Sendable {
    public let text: String
    public let actualModel: String?
    public let usage: AgentUsage
}

private struct UsageRecord: Encodable {
    let provider: AgentProvider
    let requestedModel: String
    let actualModel: String?
    let startedAt: Date
    let elapsedSeconds: Double
    let outcome: String
    let usage: AgentUsage
}

public struct AgentRunner: Sendable {
    let location: StoreLocation
    let notifications: AgentExpiryNotifications
    let server: URL

    public init(location: StoreLocation, server: URL? = nil, notifications: AgentExpiryNotifications = .shared) throws {
        guard let executable = server ?? Bundle.main.url(forAuxiliaryExecutable: "FloatMCP")
        else { throw AgentError.missingExecutable("FloatMCP") }
        self.server = executable
        self.location = location
        self.notifications = notifications
    }

    public func run(_ prompt: String, engine: AgentEngine, installation: AgentInstallation,
                    runID: UUID = UUID(), taskName: String = "에이전트 작업", timeout: Duration = .seconds(120),
                    onEvent: @escaping @Sendable (AgentEvent) -> Void = { _ in }) async throws -> AgentResult {
        let provider: AgentProvider
        let requested = engine.model
        switch engine {
        case .claude: provider = .claude
        case .codex: provider = .codex
        case .apiKey: throw AgentError.unsupportedEngine
        }
        if let requested {
            let base = provider == .claude && requested.hasSuffix("[1m]") ? requested.dropLast(4) : requested[...]
            guard !base.isEmpty, requested.utf8.count <= 128,
              base.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._:/".contains($0)) })
            else { throw AgentError.invalidOutput }
        }
        let connection = try AgentConnection(provider: provider, location: location)
        do {
            return try await executeRun(prompt, runID: runID, provider: provider, requested: requested, connection: connection,
                                        installation: installation, timeout: timeout, onEvent: onEvent)
        } catch let error as AgentError {
            switch error {
            case .failed, .providerFailure, .invalidOutput:
                guard let account = try? await connection.account(installation), connection.isExpired(account) else { throw error }
                // 알림을 보내지 못해도 만료 오류는 그대로 돌려준다.
                try? await notifications.blocked(connection, taskName: taskName)
                throw AgentError.loginExpired
            default: throw error
            }
        }
    }

    private func executeRun(_ prompt: String, runID: UUID, provider: AgentProvider, requested: String?, connection: AgentConnection,
                            installation: AgentInstallation, timeout: Duration,
                            onEvent: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentResult {
        try await onWorker {
            let id = runID.uuidString
            let folder = connection.state.appending(path: "agents/runs/\(id)", directoryHint: .isDirectory)
            let cwd = folder.appending(path: "work", directoryHint: .isDirectory)
            let log = location.stateDirectory.appending(path: "agent-usage", directoryHint: .isDirectory)
            let fm = FileManager.default
            try fm.createDirectory(at: log, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: cwd, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let date = Date()
            let start = ContinuousClock.now
            var stream = AgentStream(provider: provider)
            let result = Result {
                let args = try arguments(provider, requested, prompt, cwd, folder)
                let command = try connection.command(installation, args, directory: cwd)
                let code = try command.execute(timeout: timeout) { try stream.accept($0, emit: onEvent) }
                guard code == 0 else { throw AgentError.failed(code) }
                guard stream.started, stream.completed else { throw AgentError.invalidOutput }
                return AgentResult(text: stream.response, actualModel: stream.model, usage: stream.usage)
            }
            let elapsed = start.duration(to: .now).components
            let outcome: String
            switch result {
            case .success: outcome = "success"
            case .failure(is CancellationError): outcome = "cancelled"
            case .failure(AgentError.timeout): outcome = "timeout"
            case .failure(AgentError.isolation): outcome = "isolation"
            case .failure: outcome = "failed"
            }
            let record = UsageRecord(provider: provider, requestedModel: requested ?? "auto", actualModel: stream.model,
                                     startedAt: date, elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                                     outcome: outcome, usage: stream.usage)
            try fm.removeItem(at: folder)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: log.appending(path: "\(id).json"), options: .atomic)
            return try result.get()
        }
    }

    private func arguments(_ provider: AgentProvider, _ model: String?, _ prompt: String, _ cwd: URL, _ folder: URL) throws -> [String] {
        let notes = location.notesDirectory.path
        if provider == .claude {
            let config = folder.appending(path: "mcp.json")
            let data = try JSONSerialization.data(withJSONObject: ["mcpServers": ["float": ["command": server.path, "args": [notes]]]])
            try data.write(to: config, options: .atomic)
            return ["-p"] + (model.map { ["--model", $0] } ?? []) + ["--setting-sources", "", "--strict-mcp-config", "--mcp-config", config.path,
                    "--tools", "", "--allowedTools", AgentStream.claudeTools.joined(separator: ","), "--disable-slash-commands",
                    "--permission-mode", "dontAsk", "--no-session-persistence", "--output-format", "stream-json",
                    "--verbose", "--include-partial-messages", "--", prompt]
        }
        func literal(_ value: String) throws -> String {
            String(decoding: try JSONEncoder.tomlString.encode(value), as: UTF8.self)
        }
        let settings = try ["mcp_servers.float.command=" + literal(server.path), "mcp_servers.float.args=[" + literal(notes) + "]",
                            "mcp_servers.float.enabled_tools=[\"list_notes\",\"read_note\"]",
                            "mcp_servers.float.required=true", "mcp_servers.float.default_tools_approval_mode=\"approve\"",
                            "approval_policy=\"never\"", "web_search=\"disabled\"", "features.shell_tool=false",
                            "features.unified_exec=false", "features.hooks=false", "features.apps=false", "features.plugins=false",
                            "features.multi_agent=false", "agents.enabled=false", "plugins._default.enabled=false",
                            "skills.bundled.enabled=false", "skills.include_instructions=false"]
        return ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
                "-C", cwd.path, "-s", "read-only"] + (model.map { ["-m", $0] } ?? []) + settings.flatMap { ["-c", $0] } + ["--", prompt]
    }
}

private extension JSONEncoder {
    static var tomlString: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
