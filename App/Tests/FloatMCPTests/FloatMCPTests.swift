import Foundation
import Models
import Testing

private final class BundleMarker: NSObject {}

@Suite struct FloatMCPTests {
    private typealias Object = [String: Any]

    @Test(arguments: [false, true]) func stdioRoundTrip(proposals: Bool) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let notes = root.appending(path: "notes")
        try fm.createDirectory(at: notes, withIntermediateDirectories: true)
        defer { try! fm.removeItem(at: root) }
        let markdown = "# 메모\n본문\n[ ] 할 일\n[ ] "
        try markdown.write(to: notes.appending(path: "메모.md"), atomically: true, encoding: .utf8)
        let outside = root.appending(path: "outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: notes.appending(path: "link.md"), withDestinationURL: outside)
        try fm.createDirectory(at: notes.appending(path: "directory.md"), withIntermediateDirectories: false)
        try fm.createDirectory(at: notes.appending(path: ".trash"), withIntermediateDirectories: false)

        try "숨김".write(to: notes.appending(path: ".trash/삭제.md"), atomically: true, encoding: .utf8)
        let old = notes.appending(path: "older.md")
        try "---\ntitle: 계획\nspace: work\narchived: true\nreminder: 2026-11-24T10:00:00Z\n---\n[ ] 남음\n[x] 끝\n  - [x]  \t\n[ ] ".write(to: old, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        let bundle = Bundle(for: BundleMarker.self).bundleURL
        let candidates = [bundle.deletingLastPathComponent(), Bundle.main.bundleURL.deletingLastPathComponent(),
                          URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
        let process = Process()
        let executable = candidates.map { $0.appending(path: "FloatMCP") }.first { fm.isExecutableFile(atPath: $0.path) }
        let binary = try #require(executable)
        process.executableURL = binary
        let inbox = root.appending(path: "inbox")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let message = "말투는 이렇게 정하면 좋겠어요. 답은 두 문장 이내로 부탁드려요."
        let before = "원래 지침"
        if proposals {
            let context = AgentNoteContext(windows: ["older": .init(.init(isPinned: false, isOpen: true))],
                                           spaces: ["work": "업무"], archiveCutoff: .distantPast)
            let url = inbox.appending(path: AgentNoteContext.filename)
            try JSONEncoder().encode(context).write(to: url)
            try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
            let request = AgentRequest(id: UUID(), text: message, engine: "fixture", model: nil)
            let evidence = InstructionEvidence(request: request, instructions: before)
            try JSONEncoder().encode(evidence).write(to: inbox.appending(path: InstructionEvidence.filename))
        }
        process.arguments = [notes.path] + (proposals ? [inbox.path] : [])
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        func send(_ method: String, id: Any?, _ params: Object = [:]) throws {
            var req: Object = ["jsonrpc": "2.0", "method": method, "params": params]
            req["id"] = id
            var data = try JSONSerialization.data(withJSONObject: req)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send("initialize", id: "start", ["protocolVersion": "2025-06-18"])
        try send("notifications/initialized", id: nil)
        try send("tools/list", id: 1)
        try send("tools/call", id: 2, ["name": "list_notes", "arguments": [:]])
        for (index, name) in ["메모.md", "../outside.md", "link.md", ".hidden.md", "directory.md"].enumerated() {
            try send("tools/call", id: index + 3, ["name": "read_note", "arguments": ["name": name]])
        }
        try send("tools/call", id: 8, ["name": "add_todo"])
        var submissions: [Object] = [
            ["kind": "add_todos", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "unknown", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "../outside", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "link", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "메모", "lines": [String(repeating: "a", count: 1025)]]
        ]
        let reminder: Object = ["kind": "add_reminder", "note_id": "메모", "title": "반납", "date_only": true,
                                "start": "2028-02-29", "time_zone": "Asia/Seoul"]
        let event = reminder.merging(["kind": "add_event", "date_only": false, "start": "2028-02-29T14:30:00", "end": "2028-02-29T15:30:00"]) { _, new in new }
        let newNote: Object = ["kind": "create_note", "title": "정리", "markdown": "본문"]
        submissions += [reminder, event, newNote, event, reminder.merging(["start": "2027-02-29"]) { _, n in n },
                        event.merging(["end": "2028-02-28T15:30:00"]) { _, n in n },
                        reminder.merging(["time_zone": "없는 시간대"]) { _, n in n },
                        newNote.merging(["note_id": "link"]) { _, n in n }]
        let instruction: Object = ["kind": "change_instructions", "user_message": message, "before": before, "after": "짧은 답"]
        let instructionCases: [(arguments: Object, error: ProposalArguments.Invalid?)] = [
            (instruction, nil),
            (instruction.filter { $0.key != "user_message" }, .missingMessage),
            (instruction.merging(["user_message": "# 메모\n본문"]) { _, new in new }, .evidence),
            (instruction.merging(["user_message": message + " "]) { _, new in new }, .evidence),
            (instruction.merging(["before": before + " "]) { _, new in new }, .instructionBase)
        ]
        let instructionOffset = 9 + submissions.count
        submissions += instructionCases.map(\.arguments)
        for (i, submission) in submissions.enumerated() {
            try send("tools/call", id: 9 + i, ["name": "propose_change", "arguments": submission])
        }
        for args: Object in [["limit": 1, "offset": 1], ["since": "2000-01-01T00:00:00Z"], ["limit": false]] {
            try send("tools/call", id: 200, ["name": "list_notes", "arguments": args])
        }
        try input.fileHandleForWriting.close()
        let bytes = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let responses = try bytes.split(separator: 10).map { data in
            try #require(JSONSerialization.jsonObject(with: Data(data)) as? Object)
        }
        try #require(responses.count == 12 + submissions.count)
        #expect(responses[0]["id"] as? String == "start")
        #expect((responses[0]["result"] as? Object)?["protocolVersion"] as? String == "2025-06-18")
        let tools = (responses[1]["result"] as? Object)?["tools"] as? [Object]
        #expect(tools?.compactMap { $0["name"] as? String } == ["list_notes", "read_note"] + (proposals ? ["propose_change"] : []))
        func text(_ i: Int) -> String? {
            let content = (responses[i]["result"] as? Object)?["content"] as? [Object]
            return content?.first?["text"] as? String
        }
        let files = try fm.contentsOfDirectory(atPath: inbox.path).filter { $0 != InstructionEvidence.filename && $0 != AgentNoteContext.filename }
        #expect(files.count == (proposals ? 5 : 0))
        #expect(files.allSatisfy { $0.hasSuffix(".json") })
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
        #expect(try Data(contentsOf: notes.appending(path: "메모.md")) == Data(markdown.utf8))
        if proposals {
            for (offset, entry) in instructionCases.enumerated() {
                let i = instructionOffset + offset
                let result = try #require(responses[i]["result"] as? Object)
                if let error = entry.error {
                    #expect(result["isError"] as? Bool == true)
                    #expect(text(i) == error.errorDescription)
                } else {
                    #expect(result["isError"] == nil)
                    #expect(text(i) == "검토할 제안을 접수했습니다.")
                }
            }
            #expect(text(9) == text(10))
            for i in Array(11...14) + Array(19...22) {
                #expect((responses[i]["result"] as? Object)?["isError"] as? Bool == true)
                #expect(text(i)?.isEmpty == false)
            }
        } else {
            for i in 9..<(responses.count - 3) { #expect((responses[i]["error"] as? Object)?["code"] as? Int == -32602) }
        }
        func page(_ index: Int) throws -> [Object] {
            let value = try #require(text(index))
            let object = try #require(JSONSerialization.jsonObject(with: Data(value.utf8)) as? Object)
            return try #require(object["notes"] as? [Object])
        }
        let all = try page(2)
        #expect(all.compactMap { $0["name"] as? String } == ["메모.md", "older.md"])
        let older = try #require(all.last)
        #expect(older["title"] as? String == "계획")
        #expect(older["archived"] as? Bool == true)
        if proposals {
            #expect(older["space"] as? String == "업무")
            #expect(older["open"] as? Bool == true && older["pinned"] as? Bool == false)
        }
        #expect(older["nearest_reminder"] is Object)
        #expect(older["todo_total"] as? Int == 2 && older["todo_remaining"] as? Int == 1)
        #expect(try page(responses.count - 3).first?["name"] as? String == "older.md")
        #expect(try page(responses.count - 2).count == 1)
        #expect((responses.last?["result"] as? Object)?["isError"] as? Bool == true)
        let read = try #require(text(3)?.components(separatedBy: "\n\n[원문]\n").first)
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(read.utf8)) as? Object)
        #expect(metadata["todo_total"] as? Int == 1 && metadata["todo_remaining"] as? Int == 1)
        #expect(text(3)?.hasSuffix("\n\n[원문]\n# 메모\n본문\n[ ] 할 일\n[ ] ") == true)
        for i in 4...7 { #expect((responses[i]["result"] as? Object)?["isError"] as? Bool == true) }
        #expect((responses[8]["error"] as? Object)?["code"] as? Int == -32602)
        #expect(try fm.contentsOfDirectory(atPath: notes.path).sorted() == [".trash", "directory.md", "link.md", "older.md", "메모.md"])
    }
}
