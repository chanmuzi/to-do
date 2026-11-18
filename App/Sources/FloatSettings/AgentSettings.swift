import AgentRunner
import Foundation
import Observation
import Store

/// 엔진마다 한 작업만 진행한다. 로그인 출력과 이메일 원문은 화면 상태에 보관하지 않는다.
@Observable
package final class EngineAccount {
    package enum Status: Equatable { case unknown, missing, signedOut, connected(String), unavailable }
    package enum Activity { case checking, login, testing }
    package let provider: AgentProvider
    package private(set) var status = Status.unknown
    package private(set) var activity: Activity?
    package private(set) var message: String?
    private let location: StoreLocation
    private let searchDirectory: URL?
    private let server: URL?
    private var installation: AgentInstallation?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(_ provider: AgentProvider, location: StoreLocation, searchDirectory: URL?, server: URL?) {
        self.provider = provider
        self.location = location
        self.searchDirectory = searchDirectory
        self.server = server
    }

    var name: String { provider == .claude ? "Claude" : "Codex" }
    package var detail: String {
        switch activity {
        case .login: return "브라우저에서 로그인을 마치면 자동으로 확인해요"
        case .testing: return "시작 이벤트를 검사하고 있어요"
        case .checking: return "확인 중"
        case nil: break
        }
        if let message { return message }
        switch status {
        case .unknown: return "확인 전"
        case .missing: return "설치 안 됨"
        case .signedOut: return "로그인 전"
        case .unavailable: return "상태를 확인할 수 없어요"
        case .connected(let label): return label.isEmpty ? "연결됨" : "연결됨: " + label
        }
    }

    package func refresh() {
        start(.checking) {
            self.status = .unavailable
            self.installation = nil
            let connection = try self.connection()
            let found = try await connection.discover(in: self.searchDirectory)
            self.installation = found
            try await self.readAccount(connection, found)
        }
    }

    package func login() {
        guard status == .signedOut, let installation else { return }
        start(.login) {
            let connection = try self.connection()
            try await connection.loginCommand(installation).waitForLogin()
            try await self.readAccount(connection, installation)
        }
    }

    private func readAccount(_ connection: AgentConnection, _ installation: AgentInstallation) async throws {
        let account = try await connection.account(installation)
        let label = [account.emailDomain, account.subscription ?? account.tier ?? account.method].compactMap { $0 }.joined(separator: ", ")
        status = account.loggedIn ? .connected(label) : .signedOut
    }

    package func testConnection() {
        guard case .connected = status, let installation else { return }
        start(.testing) {
            let engine: AgentEngine = self.provider == .claude ? .claude(.haiku) : .codex()
            let runner = try AgentRunner(location: self.location, server: self.server)
            let start = ContinuousClock.now
            do {
                _ = try await runner.run("도구를 쓰지 말고 OK라고만 답하세요.", engine: engine, installation: installation)
                self.message = "시작 이벤트 확인, " + Self.elapsed(since: start)
            } catch is CancellationError { throw CancellationError() }
            catch {
                self.message = Self.description(error) + ", " + Self.elapsed(since: start)
            }
        }
    }

    package func cancel() { task?.cancel() }
    package func wait() async { await task?.value }

    private func connection() throws -> AgentConnection { try AgentConnection(provider: provider, location: location) }

    private func start(_ operation: Activity, perform: @escaping () async throws -> Void) {
        guard task == nil else { return }
        message = nil
        activity = operation
        task = Task {
            defer {
                task = nil
                activity = nil
            }
            do { try await perform() }
            catch is CancellationError { }
            catch AgentError.missingExecutable(let name) where operation == .checking && name == provider.rawValue {
                status = .missing
            } catch { message = Self.description(error) }
        }
    }

    private static func elapsed(since start: ContinuousClock.Instant) -> String {
        start.duration(to: .now).formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 2)))
    }

    private static func description(_ error: Error) -> String {
        switch error {
        case AgentError.timeout: "시간 초과"
        case AgentError.isolation: "시작 또는 도구 이벤트 검사 실패"
        case AgentError.missingExecutable(let name): name + " 실행 파일을 찾을 수 없어요"
        case AgentError.invalidOutput: "CLI 응답 형식을 확인할 수 없어요"
        case AgentError.failed(let code): "CLI 실행 실패 (종료 코드 \(code))"
        default: "실행 실패: " + error.localizedDescription
        }
    }
}

package final class AgentSettings {
    package let engines: [EngineAccount]
    package init(location: StoreLocation, searchDirectory: URL? = nil, server: URL? = nil) {
        engines = [AgentProvider.claude, .codex].map { EngineAccount($0, location: location, searchDirectory: searchDirectory, server: server) }
    }

    func refresh() { engines.forEach { $0.refresh() } }
    package var hasActiveTasks: Bool { engines.contains { $0.activity != nil } }
    package func cancel() { engines.forEach { $0.cancel() } }
    package func wait() async { for engine in engines { await engine.wait() } }
}
