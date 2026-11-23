import AgentRunner
import Foundation
import Observation
import Store

@Observable
package final class EngineAccount {
    package enum Status: Equatable { case unknown, missing, signedOut, connected, expired, unavailable }
    package enum Activity { case checking, login, logout }
    package let provider: AgentProvider
    package private(set) var status = Status.unknown
    package private(set) var activity: Activity?
    package private(set) var account: AgentAccount?
    package private(set) var message: String?
    package private(set) var models: [CodexModel] = []
    @ObservationIgnored var didLoadModels: (([CodexModel]) -> Void)?
    private var requestedModels = false
    private let location: StoreLocation
    private let directory: URL?
    private var installation: AgentInstallation?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(_ provider: AgentProvider, location: StoreLocation, directory: URL?) {
        self.provider = provider
        self.location = location
        self.directory = directory
    }

    var name: String { provider == .claude ? "Claude" : "Codex" }
    var company: String { provider == .claude ? "Anthropic" : "OpenAI" }
    package var detail: String {
        if activity == .login { return "브라우저에서 로그인 중" }
        if activity != nil { return "확인 중" }
        switch status {
        case .unknown: return "확인 전"
        case .unavailable: return "확인 실패"
        case .missing: return "설치 필요"
        case .signedOut: return "연결 안 됨"
        case .connected: return "연결됨"
        case .expired: return "다시 로그인 필요"
        }
    }

    package func refresh() {
        start(.checking) { connection in
            let found = try await connection.discover(in: self.directory)
            try Task.checkCancellation()
            self.installation = found
            if self.provider == .codex && !self.requestedModels {
                self.requestedModels = true
                let catalog = await connection.models(found)
                try Task.checkCancellation()
                if let catalog {
                    self.models = catalog
                    self.didLoadModels?(catalog)
                }
            }
            try await self.readAccount(connection, found)
        }
    }

    package func login() {
        guard [.signedOut, .expired].contains(status), let installation else { return }
        start(.login) { connection in
            try await connection.loginCommand(installation).waitForLogin()
            try Task.checkCancellation()
            self.activity = .checking
            try await self.readAccount(connection, installation)
        }
    }

    #if DEBUG
    /// 화면 배치 검사에서 CLI를 실행하지 않고 표시할 계정 상태를 만든다.
    convenience init(previewing status: Status, activity: Activity? = nil, location: StoreLocation) {
        self.init(.codex, location: location, directory: nil)
        self.status = status
        self.activity = activity
    }

    package func loginForVerification() {
        guard let directory, FileManager.default.fileExists(atPath: directory.appending(path: "float-fake-cli").path) else { return }
        login()
    }
    #endif

    package func logout() {
        guard status == .connected, let installation else { return }
        start(.logout) { connection in
            try await connection.logout(installation)
            try Task.checkCancellation()
            self.account = nil
            self.status = .signedOut
        }
    }

    private func readAccount(_ connection: AgentConnection, _ installation: AgentInstallation) async throws {
        let next = try await connection.account(installation)
        try Task.checkCancellation()
        if connection.isExpired(next) {
            if next.email != nil || account == nil { account = next }
            status = .expired
        } else if next.loggedIn {
            account = next
            status = .connected
            try await AgentExpiryNotifications.shared.reconnected(connection)
        } else {
            account = nil
            status = .signedOut
        }
    }

    package func cancel() { task?.cancel() }
    package func wait() async { await task?.value }

    func close() {
        generation += 1
        task?.cancel()
        task = nil
        account = nil
        status = .unknown
        activity = nil
        message = nil
        installation = nil
        models = []
        requestedModels = false
    }

    private func start(_ operation: Activity, perform: @escaping (AgentConnection) async throws -> Void) {
        guard task == nil else { return }
        activity = operation
        message = nil
        let started = generation
        task = Task {
            do {
                try Task.checkCancellation()
                try await perform(AgentConnection(provider: provider, location: location))
            }
            catch is CancellationError { }
            catch AgentError.missingExecutable where !Task.isCancelled {
                status = .missing
                account = nil
                installation = nil
            } catch {
                if !Task.isCancelled {
                    if operation == .checking { status = .unavailable; account = nil }
                    message = "에이전트 상태를 확인하지 못했어요"
                }
            }
            // 닫고 다시 연 창의 작업은 건드리지 않는다.
            if generation == started {
                task = nil
                activity = nil
            }
        }
    }
}

package final class AgentSettings {
    package let engines: [EngineAccount]
    package init(location: StoreLocation, searchDirectory: URL? = nil) {
        engines = [AgentProvider.claude, .codex].map { EngineAccount($0, location: location, directory: searchDirectory) }
    }
    func refresh() { engines.forEach { $0.refresh() } }
    func refreshMissing() { engines.filter { $0.status == .missing }.forEach { $0.refresh() } }
    func close() { engines.forEach { $0.close() } }
    package var hasActiveTasks: Bool { engines.contains { $0.activity != nil } }
    package func cancel() { engines.forEach { $0.cancel() } }
    package func wait() async { for engine in engines { await engine.wait() } }
}
