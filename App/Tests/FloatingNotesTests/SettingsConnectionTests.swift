import Foundation
import FloatSettings
import Store
import Testing

@Suite struct SettingsConnectionTests {
    @Test func isolatedLoginAndProbe() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: folder) }
        let agents = AgentSettings(location: .isolated(notesDirectory: folder), searchDirectory: folder, server: folder.appending(path: "fake-mcp"))
        let claude = agents.engines[0]
        claude.refresh()
        await claude.wait()
        #expect(claude.status == .missing)
        try writeCLI("claude", in: folder, script: #"""
        case "$1 $2" in
          "--version ") echo fake ;;
          "auth status")
            if test -f "$CLAUDE_CONFIG_DIR/connected"; then
              echo '{"loggedIn":true,"email":"person@example.test","subscriptionType":"Max"}'
            else echo '{"loggedIn":false}'; exit 1; fi ;;
          "auth login")
            if test -f "$(dirname "$0")/delay"; then sleep 10; fi
            touch "$CLAUDE_CONFIG_DIR/connected" ;;
          "-p --model")
            test "$3" = haiku || exit 3
            echo '{"type":"system","subtype":"init","tools":["mcp__float__list_notes","mcp__float__read_note"],"mcp_servers":[{"name":"float","status":"connected"}],"plugins":[],"skills":[],"slash_commands":[],"model":"fake-haiku"}'
            echo '{"type":"result","is_error":false,"subtype":"success","result":"OK"}' ;;
          *) exit 2 ;;
        esac
        """#)
        claude.refresh()
        await claude.wait()
        #expect(claude.status == .signedOut)
        let delay = folder.appending(path: "delay")
        try Data().write(to: delay)
        claude.login()
        #expect(claude.activity == .login)
        claude.refresh()
        #expect(claude.activity == .login)
        try await Task.sleep(for: .milliseconds(60))
        claude.cancel()
        await claude.wait()
        #expect(claude.activity == nil && claude.status == .signedOut)
        try FileManager.default.removeItem(at: delay)
        claude.login()
        await claude.wait()
        #expect(claude.status == .connected("example.test, Max"))
        claude.testConnection()
        await claude.wait()
        #expect(claude.message?.hasPrefix("시작 이벤트 확인, ") == true)
    }

    @Test func codexDefaultModelAndInvalidStart() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: folder) }
        try writeCLI("node", in: folder, script: "exit 99")
        try writeCLI("codex", in: folder, script: #"""
        case "$1" in
          --version) echo fake ;;
          login) test "$2" = status; echo "Logged in using ChatGPT" >&2 ;;
          exec)
            for arg do test "$arg" != -m || exit 2; done
            if test -f "$(dirname "$0")/invalid"; then echo '{"type":"turn.completed"}'; exit; fi
            echo '{"type":"thread.started"}'
            echo '{"type":"turn.completed"}' ;;
          *) exit 2 ;;
        esac
        """#)
        let agents = AgentSettings(location: .isolated(notesDirectory: folder), searchDirectory: folder, server: folder.appending(path: "fake-mcp"))
        let codex = agents.engines[1]
        codex.refresh()
        await codex.wait()
        #expect(codex.status == .connected("ChatGPT"))
        codex.testConnection()
        await codex.wait()
        #expect(codex.message?.hasPrefix("시작 이벤트 확인, ") == true)
        try Data().write(to: folder.appending(path: "invalid"))
        codex.testConnection()
        await codex.wait()
        #expect(codex.message?.contains("응답 형식") == true)
    }

    private func writeCLI(_ name: String, in folder: URL, script: String) throws {
        let file = folder.appending(path: name)
        try ("#!/bin/sh\nset -e\n" + script).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }
}
