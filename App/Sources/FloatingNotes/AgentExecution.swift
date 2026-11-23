import AgentRunner
import Foundation
import Models
import Store

struct AgentExecution {
    let location: StoreLocation
    let directory: URL?
    var server: URL?
    var notifications: AgentExpiryNotifications = .shared

    func run(_ conversation: AgentConversation, _ request: AgentRequest,
             emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> String {
        let provider = AgentProvider(rawValue: request.engine) ?? .claude
        let connection = try AgentConnection(provider: provider, location: location)
        let installation: AgentInstallation
        do { installation = try await connection.discover(in: directory) }
        catch AgentError.missingExecutable {
            throw AgentRequestCoordinator.Failure(message: "에이전트 설치가 필요해요", settings: true)
        }
        let account = try await connection.account(installation)
        if connection.isExpired(account) {
            try? await notifications.blocked(connection, taskName: "에이전트 작업")
            throw AgentRequestCoordinator.Failure(message: "로그인이 만료됐어요", settings: true)
        }
        guard account.loggedIn else { throw AgentRequestCoordinator.Failure(message: "에이전트 연결이 필요해요", settings: true) }
        let prompt = try Self.prompt(conversation, request, instructions: AgentStore(location: location).readInstructions())
        let runner = try AgentRunner(location: location, server: server, notifications: notifications)
        do {
            let engine: AgentEngine = provider == .claude ? .claude(request.model) : .codex(model: request.model)
            return try await runner.run(prompt, engine: engine, installation: installation, runID: request.runID, onEvent: emit).text
        } catch AgentError.loginExpired {
            throw AgentRequestCoordinator.Failure(message: "로그인이 만료됐어요", settings: true)
        } catch AgentError.rateLimited(let reset) {
            throw AgentRequestCoordinator.Failure(message: "사용 한도에 도달했어요", resumeAt: reset.map(Date.init(timeIntervalSince1970:)))
        } catch AgentError.isolation("process_group") {
            throw AgentError.isolation("process_group")
        } catch is CancellationError { throw CancellationError() }
        catch {
            let version = installation.version.split { !$0.isNumber && $0 != "." }.first { $0.contains(".") } ?? ""
            throw AgentRequestCoordinator.Failure(message: "\(provider == .claude ? "Claude" : "Codex") \(version) 요청을 마치지 못했어요")
        }
    }

    private struct Prompt: Encodable {
        var instructions: String
        var targets: [String]
        var history: [AgentConversation.Message]
        var omittedMessages = 0
        var request: String
    }

    private static func prompt(_ conversation: AgentConversation, _ request: AgentRequest, instructions: String) throws -> String {
        let history = conversation.messages.prefix { $0.requestID != request.id }
        var prompt = Prompt(instructions: instructions, targets: conversation.targets.map { $0.rawValue + ".md" },
                            history: [], omittedMessages: history.count, request: request.userText)
        let encoder = JSONEncoder()
        let limit = 96 * 1024
        guard try encoder.encode(prompt).count <= limit else {
            throw AgentRequestCoordinator.Failure(message: "요청이나 지침이 너무 길어요")
        }
        for message in history.reversed() {
            prompt.history.insert(message, at: 0)
            prompt.omittedMessages -= 1
            if try encoder.encode(prompt).count > limit {
                prompt.history.removeFirst()
                prompt.omittedMessages += 1
                break
            }
        }
        return String(decoding: try encoder.encode(prompt), as: UTF8.self)
    }
}

#if DEBUG
struct VerificationExpiryNotifier: AgentExpiryNotifying {
    func notify(_ provider: AgentProvider, taskName: String) async throws {}
}
#endif
