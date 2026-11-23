import Foundation
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
        try "# 메모\n본문".write(to: notes.appending(path: "메모.md"), atomically: true, encoding: .utf8)
        let outside = root.appending(path: "outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: notes.appending(path: "link.md"), withDestinationURL: outside)
        try fm.createDirectory(at: notes.appending(path: "directory.md"), withIntermediateDirectories: false)
        try fm.createDirectory(at: notes.appending(path: ".trash"), withIntermediateDirectories: false)

        let bundle = Bundle(for: BundleMarker.self).bundleURL
        let candidates = [bundle.deletingLastPathComponent(), Bundle.main.bundleURL.deletingLastPathComponent(),
                          URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
        let process = Process()
        let executable = candidates.map { $0.appending(path: "FloatMCP") }.first { fm.isExecutableFile(atPath: $0.path) }
        let binary = try #require(executable)
        process.executableURL = binary
        let inbox = root.appending(path: "inbox")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
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
        let submissions: [Object] = [
            ["kind": "add_todos", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "unknown", "note_id": "메모", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "../outside", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "link", "lines": ["약속 확인"]],
            ["kind": "add_todos", "note_id": "메모", "lines": [String(repeating: "a", count: 1025)]]
        ]
        for (i, submission) in submissions.enumerated() {
            try send("tools/call", id: 9 + i, ["name": "propose_change", "arguments": submission])
        }
        try input.fileHandleForWriting.close()
        let bytes = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let responses = try bytes.split(separator: 10).map { data in
            try #require(JSONSerialization.jsonObject(with: Data(data)) as? Object)
        }
        try #require(responses.count == 15)
        #expect(responses[0]["id"] as? String == "start")
        #expect((responses[0]["result"] as? Object)?["protocolVersion"] as? String == "2025-06-18")
        let tools = (responses[1]["result"] as? Object)?["tools"] as? [Object]
        #expect(tools?.compactMap { $0["name"] as? String } == ["list_notes", "read_note"] + (proposals ? ["propose_change"] : []))
        func text(_ i: Int) -> String? {
            let content = (responses[i]["result"] as? Object)?["content"] as? [Object]
            return content?.first?["text"] as? String
        }
        let files = try fm.contentsOfDirectory(atPath: inbox.path)
        #expect(files.count == (proposals ? 1 : 0))
        #expect(files.allSatisfy { $0.hasSuffix(".json") })
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
        #expect(try Data(contentsOf: notes.appending(path: "메모.md")) == Data("# 메모\n본문".utf8))
        if proposals {
            #expect(text(9) == text(10))
            for i in 11...14 {
                #expect((responses[i]["result"] as? Object)?["isError"] as? Bool == true)
                #expect(text(i)?.isEmpty == false)
            }
        } else {
            for i in 9...14 { #expect((responses[i]["error"] as? Object)?["code"] as? Int == -32602) }
        }
        #expect(text(2) == "메모.md")
        #expect(text(3) == "# 메모\n본문")
        for i in 4...7 { #expect((responses[i]["result"] as? Object)?["isError"] as? Bool == true) }
        #expect((responses[8]["error"] as? Object)?["code"] as? Int == -32602)
        #expect(try fm.contentsOfDirectory(atPath: notes.path).sorted() == [".trash", "directory.md", "link.md", "메모.md"])
    }
}
