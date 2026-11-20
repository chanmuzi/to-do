import Foundation
import FloatSettings
import Store
import Testing

@Suite struct AgentStateTransitionTests {
    @Test func isolatedLoginCancelVerifyExpiryAndLogout() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: folder) }
        let location = StoreLocation.isolated(notesDirectory: folder)
        let engine = AgentSettings(location: location, searchDirectory: folder).engines[0]
        engine.refresh()
        await engine.wait()
        #expect(engine.status == .missing)
        let cli = folder.appending(path: "claude")
        try #"""
        #!/bin/sh
        set -eu
        case "$1 ${2:-}" in
          "--version ") echo fake ;;
          "auth status")
            if test -f "$CLAUDE_CONFIG_DIR/connected"; then
              sleep 0.2
              echo '{"loggedIn":true,"email":"me@example.com","subscriptionType":"Max"}'
            else echo '{"loggedIn":false}'; exit 1; fi ;;
          "auth login")
            if test -f "$(dirname "$0")/delay"; then sleep 10; fi
            touch "$CLAUDE_CONFIG_DIR/connected" ;;
          "auth logout") rm "$CLAUDE_CONFIG_DIR/connected" ;;
          *) exit 2 ;;
        esac
        """#.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        engine.refresh()
        await engine.wait()
        #expect(engine.status == .signedOut)
        let delay = folder.appending(path: "delay")
        try Data().write(to: delay)
        engine.login()
        #expect(engine.activity == .login)
        engine.refresh()
        #expect(engine.activity == .login)
        try await Task.sleep(for: .milliseconds(60))
        engine.cancel()
        await engine.wait()
        #expect(engine.activity == nil && engine.status == .signedOut)
        try FileManager.default.removeItem(at: delay)
        engine.login()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while engine.activity == .login && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(engine.activity == .checking)
        await engine.wait()
        #expect(engine.status == .connected && engine.account?.email == "me@example.com")
        try FileManager.default.removeItem(at: location.stateDirectory.appending(path: "agents/claude/connected"))
        engine.refresh()
        await engine.wait()
        #expect(engine.status == .expired && engine.account?.subscription == "Max")
        engine.login()
        await engine.wait()
        engine.logout()
        await engine.wait()
        #expect(engine.status == .signedOut && engine.account == nil)
        engine.refresh()
        await engine.wait()
        #expect(engine.status == .signedOut)
    }
}
