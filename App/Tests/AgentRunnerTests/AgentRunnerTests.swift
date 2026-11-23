import Foundation
import Store
import Synchronization
import Testing
@testable import AgentRunner

private typealias Object = [String: Any]
private var initEvent: Object { [
    "type": "system", "subtype": "init", "tools": ["mcp__float__list_notes", "mcp__float__read_note"],
    "plugins": [["name": "cc-plugin-test", "path": "builtin"]], "mcp_servers": [["name": "float", "status": "connected"]],
    "skills": [], "slash_commands": [], "model": "claude-haiku-test"
] }

private struct Fixture {
    let root: URL
    let location: StoreLocation
    let installation: AgentInstallation
    let runner: AgentRunner

    init(_ provider: AgentProvider, _ body: String) throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appending(path: provider.rawValue)
        try ("#!/bin/sh\nset -eu\n" + body).write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        installation = AgentInstallation(provider: provider, executable: exe, version: "test",
                                         node: provider == .codex ? bin.appending(path: "node") : nil)
        location = StoreLocation.isolated(notesDirectory: root)
        runner = try AgentRunner(location: location, server: bin.appending(path: "Float MCP"))
    }
    func cleanup() throws { try FileManager.default.removeItem(at: root) }
    func journal() throws -> Object {
        let files = try FileManager.default.contentsOfDirectory(at: location.stateDirectory.appending(path: "agent-usage"),
                                                               includingPropertiesForKeys: nil)
        let url = try #require(files.count == 1 ? files.first : nil)
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
    }
}

@Suite struct AgentRunnerTests {
    @Test(arguments: ["fable", "opus", "sonnet", "haiku", "auto"])
    func claudeIsolationStreamAndUsage(_ model: String) async throws {
        let start = String(decoding: try JSONSerialization.data(withJSONObject: initEvent), as: UTF8.self)
        let fx = try Fixture(.claude, #"""
        test "$(ls -A)" = ""
        if read -r extra; then exit 2; fi
        dest="$(dirname "$0")"
        env > "$dest/env"
        printf '%s\n' "$@" > "$dest/args"
        while [ "$1" != "--mcp-config" ]; do shift; done
        cp "$2" "$dest/config"
        cat <<'JSON'
        \#(start)
        {"type":"stream_event","event":{"delta":{"type":"text_delta","text":"가"}}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__float__list_notes"}]}}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":10}}
        {"type":"result","is_error":false,"subtype":"success","result":"가","usage":{"input_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4,"output_tokens":5},"total_cost_usd":0.01}
        JSON
        """#)
        defer { try! fx.cleanup() }
        let events = Mutex<[AgentEvent]>([])
        let result = try await fx.runner.run("--user-prompt", engine: .claude(model), installation: fx.installation) { event in
            events.withLock { $0.append(event) }
        }
        #expect(result.text == "가")
        #expect(result.actualModel == "claude-haiku-test")
        #expect(result.usage == AgentUsage(inputTokens: 9, outputTokens: 5, costUSD: 0.01))
        #expect(events.withLock { $0 } == [.started(model: result.actualModel), .text("가"), .tool("mcp__float__list_notes"),
                                             .rateLimit(status: "allowed", resetsAt: 10), .usage(result.usage)])
        let bin = fx.installation.executable.deletingLastPathComponent()
        let args = try String(contentsOf: bin.appending(path: "args"), encoding: .utf8).components(separatedBy: "\n")
        let conf = try #require(args.firstIndex(of: "--mcp-config")).advanced(by: 1)
        let prefix = model == "auto" ? ["-p"] : ["-p", "--model", model]
        #expect(args == prefix + [ "--setting-sources", "", "--strict-mcp-config", "--mcp-config", args[conf],
                         "--tools", "", "--allowedTools", "mcp__float__list_notes,mcp__float__read_note", "--disable-slash-commands",
                         "--permission-mode", "dontAsk", "--no-session-persistence", "--output-format", "stream-json",
                         "--verbose", "--include-partial-messages", "--", "--user-prompt", ""])
        let config = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: bin.appending(path: "config"))) as? Object)
        let servers = try #require(config["mcpServers"] as? [String: Object])
        #expect(servers.count == 1)
        #expect(servers["float"]?["args"] as? [String] == [fx.root.path])
        #expect(servers["float"]?["command"] as? String == bin.appending(path: "Float MCP").path)
        let env = try String(contentsOf: bin.appending(path: "env"), encoding: .utf8)
        let connection = try AgentConnection(provider: .claude, location: fx.location)
        let command = try connection.loginCommand(fx.installation)
        #expect(command.arguments == ["auth", "login"])
        let expected = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "USER": NSUserName(), "LOGNAME": NSUserName(),
                        "PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": fx.location.stateDirectory.appending(path: "agents/claude").path,
                        "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
                        "ENABLE_CLAUDEAI_MCP_SERVERS": "false", "CLAUDE_CODE_DISABLE_BUNDLED_SKILLS": "1", "DISABLE_AUTOUPDATER": "1"]
        #expect(command.environment == expected)
        for (key, value) in expected { #expect(env.components(separatedBy: "\n").contains("\(key)=\(value)")) }
        let journal = try fx.journal()
        #expect(journal["actualModel"] as? String == result.actualModel)
        #expect(journal["outcome"] as? String == "success")
        #expect(!FileManager.default.fileExists(atPath: args[conf]))
    }

    @Test(arguments: ["tools", "mcp_servers", "plugins", "skills", "slash_commands", "missing", "beforeInit"])
    func rejectsIsolationLeak(_ field: String) async throws {
        var row = initEvent
        switch field {
        case "plugins": row[field] = [["name": "cc-plugin-user", "path": "/outside"]]
        case "mcp_servers": row[field] = [["name": "another", "status": "connected"]]
        case "missing": row.removeValue(forKey: "skills")
        case "beforeInit": row = ["type": "assistant"]
        default: row[field] = ["unexpected"]
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        let fx = try Fixture(.claude, "echo '\(json)'\nexec sleep 20")
        defer { try! fx.cleanup() }
        let reason = field == "missing" ? "skills" : field == "beforeInit" ? "init" : field
        await #expect(throws: AgentError.isolation(reason)) {
            try await fx.runner.run("prompt", engine: .claude("sonnet"), installation: fx.installation, timeout: .seconds(3))
        }
        #expect(try fx.journal()["outcome"] as? String == "isolation")
    }

    @Test(arguments: ["gpt-test", nil] as [String?])
    func codexEnvironmentAndResult(_ model: String?) async throws {
        let fx = try Fixture(.codex, #"""
        test "$(ls -A)" = ""
        test -n "$USER" && test -n "$LOGNAME"
        test "$CODEX_HOME" != "$HOME"
        test "$PATH" = "$(dirname "$0"):/usr/bin:/bin"
        if read -r extra; then exit 2; fi
        printf '%s\n' "$@" > "$(dirname "$0")/args"
        cat <<'JSON'
        {"type":"thread.started","thread_id":"test"}
        {"type":"turn.started"}
        {"type":"item.started","item":{"type":"mcp_tool_call","server":"float","tool":"list_notes"}}
        {"type":"item.completed","item":{"type":"agent_message","text":"ok"}}
        {"type":"turn.completed","usage":{"input_tokens":11,"output_tokens":3}}
        JSON
        """#)
        defer { try! fx.cleanup() }
        let result = try await fx.runner.run("prompt", engine: .codex(model: model), installation: fx.installation)
        #expect(result.text == "ok")
        #expect(result.actualModel == nil)
        #expect(result.usage == AgentUsage(inputTokens: 11, outputTokens: 3, costUSD: nil))
        let args = try String(contentsOf: fx.root.appending(path: "bin/args"), encoding: .utf8).components(separatedBy: "\n")
        #expect(Array(args.prefix(7)) == ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "-C"])
        #expect(Array(args[8..<10]) == ["-s", "read-only"])
        if let model { #expect(Array(args[10..<12]) == ["-m", model]) }
        else { #expect(!args.contains("-m")) }
        #expect(args.contains("mcp_servers.float.command=\"\(fx.runner.server.path)\""))
        #expect(args.contains("mcp_servers.float.args=[\"\(fx.root.path)\"]"))
        #expect(args.contains("features.shell_tool=false"))
        #expect(try fx.journal()["requestedModel"] as? String == (model ?? "auto"))
    }

    @Test func timeoutReapsGroup() async throws {
        let fx = try Fixture(.claude, #"sleep 20 & child=$!; echo "$child" > "${0%/*}/child"; wait"#)
        defer { try! fx.cleanup() }
        await #expect(throws: AgentError.timeout) {
            try await fx.runner.run("prompt", engine: .claude("opus"), installation: fx.installation, timeout: .seconds(2))
        }
        let child = try String(contentsOf: fx.root.appending(path: "bin/child"), encoding: .utf8)
        let pid = try #require(Int32(child.trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<50 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(try fx.journal()["outcome"] as? String == "timeout")
    }

    @Test func cancellation() async throws {
        let fx = try Fixture(.codex, #"echo ready > "$(dirname "$0")/ready"; exec sleep 20"#)
        defer { try! fx.cleanup() }
        let task = Task { try await fx.runner.run("prompt", engine: .codex(model: "gpt-test"), installation: fx.installation) }
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: fx.root.appending(path: "bin/ready").path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fx.journal()["outcome"] as? String == "cancelled")
    }

    @Test func accountAndLoginCommands() async throws {
        let address = ["person", "example.invalid"].joined(separator: "@")
        let fx = try Fixture(.claude, """
            test "$*" = 'auth status --json'
            echo '{"loggedIn":true,"authMethod":"claude.ai","email":"\(address)","subscriptionType":"max","planTier":"test","loginExpiresAt":"future"}'
            """)
        defer { try! fx.cleanup() }
        let claude = try AgentConnection(provider: .claude, location: fx.location)
        let account = try await claude.account(fx.installation)
        #expect(account.loggedIn && account.method == "claude.ai" && account.emailDomain == "example.invalid")
        #expect(account.tier == "test" && account.subscription == "max" && account.expiresAt == "future")
        let other = try Fixture(.codex, "test \"$*\" = 'login status'\necho 'Not logged in' >&2\nexit 1")
        defer { try! other.cleanup() }
        let codex = try AgentConnection(provider: .codex, location: other.location)
        #expect(try codex.loginCommand(other.installation).arguments == ["login"])
        let disconnected = try await codex.account(other.installation)
        #expect(!disconnected.loggedIn && disconnected.email == nil)
    }
}

@Suite struct CodexModelListTests {
    @Test(arguments: ["list", "empty", "failed", "wrongShape", "absent"])
    func readsOnlyVisibleModelsInPriorityOrder(_ scenario: String) async throws {
        let fx = try Fixture(.codex, #"""
        test "$*" = "debug models"
        test "$CODEX_HOME" = "$(dirname "$(dirname "$0")")/.state/agents/codex"
        case "\#(scenario)" in
          failed) exit 7 ;;
          wrongShape) echo '{"models":{}}' ;;
          empty) echo '{"models":[]}' ;;
          *) echo '{"models":[{"slug":"b","display_name":"Second","visibility":"list","priority":2},{"slug":"x","display_name":"Hidden","visibility":"hide","priority":0},{"slug":"a","display_name":"First","visibility":"list","priority":1}]}' ;;
        esac
        """#)
        defer { try! fx.cleanup() }
        if scenario == "absent" { try FileManager.default.removeItem(at: fx.installation.executable) }
        let connection = try AgentConnection(provider: .codex, location: fx.location)
        let list = await connection.models(fx.installation)
        switch scenario {
        case "list":
            #expect(list?.map(\.slug) == ["a", "b"])
            #expect(list?.map(\.displayName) == ["First", "Second"])
        case "empty":
            #expect(list?.isEmpty == true)
        default:
            #expect(list == nil)
        }
    }
}
