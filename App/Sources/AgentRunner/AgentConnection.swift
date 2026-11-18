import Foundation
import Store

public enum AgentProvider: String, Codable, Sendable { case claude, codex }
public enum ClaudeModel: String, Sendable { case opus, sonnet, haiku }
public enum APIProvider: String, Sendable { case anthropic, openAI }
public enum AgentEngine: Sendable {
    case claude(ClaudeModel), codex(model: String? = nil), apiKey(APIProvider)
}

public struct AgentAccount: Sendable {
    public let loggedIn: Bool
    public let method: String?
    /// 화면 수명 동안만 사용한다. 상태, 오류, 실행 기록에는 직렬화하지 않는다.
    public let email: String?
    public var emailDomain: String? {
        guard let email, let separator = email.lastIndex(of: "@"), separator != email.startIndex else { return nil }
        let domain = email[email.index(after: separator)...]
        return domain.isEmpty ? nil : String(domain)
    }
    public let subscription: String?
    public let tier: String?
    public let expiresAt: String?
}

public struct AgentInstallation: Sendable {
    public let provider: AgentProvider
    public let executable: URL
    public let version: String
    public let node: URL?
}

public struct AgentConnection: Sendable {
    public let provider: AgentProvider
    let state: URL
    let config: URL
    let home: URL

    public init(provider: AgentProvider, location: StoreLocation) throws {
        self.provider = provider
        state = location.stateDirectory
        let agents = state.appending(path: "agents", directoryHint: .isDirectory)
        config = agents.appending(path: provider.rawValue, directoryHint: .isDirectory)
        // 사용자 홈에서 별도로 검색하는 .agents/skills도 Codex 세션에 넣지 않는다.
        home = provider == .codex ? agents.appending(path: "codex-home") : FileManager.default.homeDirectoryForCurrentUser
        for folder in provider == .codex ? [config, home] : [config] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }

    private func baseEnvironment(node: URL?) -> [String: String] {
        let user = NSUserName()
        let path = [node?.deletingLastPathComponent().path, "/usr/bin", "/bin"].compactMap { $0 }.joined(separator: ":")
        return ["HOME": home.path, "USER": user, "LOGNAME": user, "PATH": path]
    }

    func command(_ installation: AgentInstallation, _ args: [String], directory: URL) throws -> AgentCommand {
        guard installation.provider == provider else { throw AgentError.missingExecutable(provider.rawValue) }
        var env = baseEnvironment(node: installation.node)
        if provider == .claude {
            env.merge(["CLAUDE_CONFIG_DIR": config.path, "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
                       "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
                       "CLAUDE_CODE_DISABLE_BUNDLED_SKILLS": "1", "DISABLE_AUTOUPDATER": "1"]) { _, value in value }
        } else {
            env["CODEX_HOME"] = config.path
        }
        return AgentCommand(executable: installation.executable, arguments: args, environment: env, directory: directory)
    }

    /// 흔한 경로에서 못 찾은 이름만 한 번의 로그인 셸로 확인한다. 셸에는 고정된 명령만 전달한다.
    public func discover(in directory: URL? = nil) async throws -> AgentInstallation {
        try await onWorker {
            let bins: [URL]
            if let directory {
                bins = [directory]
            } else {
                bins = Self.standardBins()
            }
            func find(_ name: String, in dirs: [URL]) -> URL? {
                dirs.map { $0.appending(path: name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
            }
            var executable = find(provider.rawValue, in: bins)
            var node: URL?
            if provider == .codex { node = find("node", in: [executable?.deletingLastPathComponent()].compactMap { $0 } + bins) }
            if directory == nil && (executable == nil || (provider == .codex && node == nil)) {
                let userHome = FileManager.default.homeDirectoryForCurrentUser
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let names = provider == .claude ? ["claude"] : ["codex", "node"]
                let query = names.map { "command -v \($0) || :" }.joined(separator: "\n")
                let lookup = AgentCommand(executable: URL(filePath: shell), arguments: ["-lc", query],
                                          environment: ["HOME": userHome.path, "USER": NSUserName(), "LOGNAME": NSUserName(),
                                                        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"], directory: config)
                let (code, data) = try lookup.capture()
                guard code == 0 else { throw AgentError.failed(code) }
                for path in String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                where path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) {
                    let url = URL(filePath: path)
                    if url.lastPathComponent == provider.rawValue { executable = url }
                    if url.lastPathComponent == "node" { node = url }
                }
            }
            guard let executable else { throw AgentError.missingExecutable(provider.rawValue) }
            if provider == .codex && node == nil { throw AgentError.missingExecutable("node") }
            let found = AgentInstallation(provider: provider, executable: executable, version: "", node: node)
            let (code, data) = try command(found, ["--version"], directory: config).capture()
            guard code == 0 else { throw AgentError.failed(code) }
            let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty else { throw AgentError.invalidOutput }
            return AgentInstallation(provider: provider, executable: executable, version: version, node: node)
        }
    }

    private static func standardBins() -> [URL] {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let nvm = userHome.appending(path: ".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
        return [userHome.appending(path: ".local/bin"), URL(filePath: "/opt/homebrew/bin"),
                    URL(filePath: "/usr/local/bin")] + versions.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }.map { $0.appending(path: "bin") }
    }

    public func loginCommand(_ installation: AgentInstallation) throws -> AgentCommand {
        try command(installation, provider == .claude ? ["auth", "login"] : ["login"], directory: config)
    }

    public func account(_ installation: AgentInstallation) async throws -> AgentAccount {
        try await onWorker {
            let args = provider == .claude ? ["auth", "status", "--json"] : ["login", "status"]
            let (status, data) = try command(installation, args, directory: config).capture(mergeDiagnostics: provider == .codex)
            if provider == .claude, let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let loggedIn = fields["loggedIn"] as? Bool, status == (loggedIn ? 0 : 1) {
                return AgentAccount(loggedIn: loggedIn, method: fields["authMethod"] as? String,
                                    email: fields["email"] as? String, subscription: fields["subscriptionType"] as? String,
                                    tier: fields["planTier"] as? String, expiresAt: fields["loginExpiresAt"] as? String)
            }
            if provider == .codex {
                let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
                let prefix = "Logged in using "
                let method = lines.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
                if (status == 0 && method != nil) || (status == 1 && lines.contains("Not logged in")) {
                    // 일부 버전은 API 키 일부를 출력한다. 인증 방식만 돌려준다.
                    let label = method.map { $0.hasPrefix("ChatGPT") ? "ChatGPT" : ($0.hasPrefix("an API key") ? "API key" : "other") }
                    return AgentAccount(loggedIn: status == 0, method: label, email: nil, subscription: nil, tier: nil, expiresAt: nil)
                }
            }
            throw status == 0 ? AgentError.invalidOutput : AgentError.failed(status)
        }
    }
}
