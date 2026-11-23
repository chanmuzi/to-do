import AgentRunner
import Foundation
import Models
import Store
import Testing
@testable import FloatingNotes

@Suite struct InstructionRequestTests {
    @Test(arguments: [AgentProvider.claude, .codex])
    func eachRunUsesItsOwnInstructionSnapshot(_ provider: AgentProvider) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = #"""
        #!/usr/bin/python3
        import sys, json, os, time
        from pathlib import Path
        args = sys.argv[1:]
        def emit(row): print(json.dumps(row), flush=True)
        if args == ["--version"]: print("2.1.999")
        elif args[:2] == ["auth", "status"]: emit({"loggedIn":True, "authMethod":"claude.ai"})
        elif args[:2] == ["login", "status"]: print("Logged in using ChatGPT")
        else:
            data = json.loads(args[-1])
            n = int(data["request"][-1])
            marker = "rule-fixture-" + str(n)
            assert data["instructions"] == marker and args[-1].count(marker) == 1
            assert len(data["history"]) == n - 1 and "propose_change" in data["toolInstruction"]
            if n == 1:
                directory = Path(__file__).parent
                (directory / "ready").touch()
                deadline = time.monotonic() + 10
                while not (directory / "continue").exists():
                    if time.monotonic() >= deadline: sys.exit(3)
                    time.sleep(.01)
            if args[0] == "-p":
                assert os.environ["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] == "1"
                emit({"type":"system","subtype":"init","model":"fixture","tools":["mcp__float__"+x for x in ["list_notes","read_note","propose_change"]],"mcp_servers":[{"name":"float","status":"connected"}],"skills":[],"plugins":[],"slash_commands":[]})
                emit({"type":"result","subtype":"success","is_error":False,"result":"ok"})
            else:
                assert args[0] == "exec" and "--ignore-rules" in args
                emit({"type":"thread.started"})
                emit({"type":"item.completed","item":{"type":"agent_message","text":"ok"}})
                emit({"type":"turn.completed"})
        """#
        for name in [provider.rawValue, "node"] {
            let file = bin.appending(path: name)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        let location = StoreLocation.isolated(notesDirectory: root)
        let store = AgentStore(location: location)
        let executor = AgentExecution(location: location, directory: bin, instructionStore: store, server: bin.appending(path: "FloatMCP"))
        var conversation = AgentConversation(targets: [])
        for n in 1...2 {
            if n == 1 { store.editInstructions("rule-fixture-1", basedOn: "") }
            let request = AgentRequest(id: UUID(), text: "fixture-message-" + String(n), engine: provider.rawValue, model: nil)
            let snapshot = conversation
            let task = Task { try await executor.run(snapshot, request) { _ in } }
            if n == 1 {
                let ready = bin.appending(path: "ready")
                for _ in 0..<300 where !FileManager.default.fileExists(atPath: ready.path) {
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(FileManager.default.fileExists(atPath: ready.path))
                store.editInstructions("rule-fixture-2", basedOn: "rule-fixture-1")
                try Data().write(to: bin.appending(path: "continue"))
            }
            let answer = try await task.value
            #expect(answer == "ok")
            conversation.messages.append(.init(role: .user, requestID: request.id, text: request.userText))
            let usage = location.stateDirectory.appending(path: "agent-usage").appending(path: request.runID.uuidString + ".json")
            let log = try String(contentsOf: usage, encoding: .utf8)
            #expect(!log.contains("rule-fixture") && !log.contains("fixture-message"))
        }
    }
}
