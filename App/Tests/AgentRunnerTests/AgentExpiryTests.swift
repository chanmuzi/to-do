import Foundation
import Store
import Testing
@testable import AgentRunner

@Suite struct AgentExpiryTests {
    private actor Notices: AgentExpiryNotifying {
        var names: [String] = []
        func notify(_ provider: AgentProvider, taskName: String) { names.append(taskName) }
    }
    @Test func blockedTaskNotifiesOnceUntilReconnect() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let location = StoreLocation.isolated(notesDirectory: root)
        let connection = try AgentConnection(provider: .claude, location: location)
        defer { try! FileManager.default.removeItem(at: root) }
        let cli = root.appending(path: "claude")
        try #"""
        #!/bin/sh
        if test "$1" = auth; then echo '{"loggedIn":false}'; exit 1; fi
        exit 9
        """#.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let installation = AgentInstallation(provider: .claude, executable: cli, version: "fake", node: nil)
        let sink = Notices()
        let notices = AgentExpiryNotifications(notifier: sink)
        let runner = try AgentRunner(location: location, server: cli, notifications: notices)
        func run() async throws { _ = try await runner.run("fake", engine: .claude("haiku"), installation: installation, taskName: "오늘 할 일 정리") }
        await #expect(throws: AgentError.failed(9)) { try await run() }
        try Data().write(to: connection.config.appending(path: ".credentials.json"))
        let account = try await connection.account(installation)
        #expect(connection.isExpired(account))
        #expect(await sink.names.isEmpty)
        for _ in 0..<2 { await #expect(throws: AgentError.loginExpired) { try await run() } }
        #expect(await sink.names == ["오늘 할 일 정리"])
        try await notices.reconnected(connection)
        await #expect(throws: AgentError.loginExpired) { try await run() }
        #expect(await sink.names.count == 2)
        let expired = AgentAccount(loggedIn: true, method: nil, email: nil, subscription: nil, tier: nil, expiresAt: "2000-01-01T00:00:00.000Z")
        #expect(connection.isExpired(expired))
    }
}
