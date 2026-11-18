import Foundation

typealias Object = [String: Any]

let tools: [Object] = [
    ["name": "list_notes", "description": "읽을 수 있는 노트 파일 이름을 나열합니다.",
     "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]],
    ["name": "read_note", "description": "목록에서 고른 노트 파일 원문을 읽습니다.",
     "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]],
                     "required": ["name"], "additionalProperties": false]]
]

@MainActor
func reply(_ line: String, notes: NoteDirectory) -> Object? {
    let decoded = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: .fragmentsAllowed)
    let request = decoded as? Object
    let id = request?["id"] ?? NSNull()
    func error(_ code: Int, _ message: String) -> Object {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
    guard decoded != nil else { return error(-32700, "Parse error") }
    guard let request, request["jsonrpc"] as? String == "2.0",
          let method = request["method"] as? String else { return error(-32600, "Invalid request") }
    guard request["id"] != nil else { return nil }
    let params = request["params"] as? Object ?? [:]
    let result: Object
    switch method {
    case "initialize":
        let version = params["protocolVersion"] as? String ?? ""
        let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
        result = ["protocolVersion": supported.contains(version) ? version : supported[0],
                  "capabilities": ["tools": [:]], "serverInfo": ["name": "float", "version": "1"]]
    case "ping": result = [:]
    case "tools/list": result = ["tools": tools]
    case "tools/call":
        guard let name = params["name"] as? String else { return error(-32602, "Missing tool name") }
        let arguments = params["arguments"] ?? Object()
        guard let args = arguments as? Object else { return error(-32602, "Invalid arguments") }
        do {
            let text: String
            switch name {
            case "list_notes" where args.isEmpty: text = try notes.list().joined(separator: "\n")
            case "read_note":
                guard args.count == 1, let filename = args["name"] as? String else { return error(-32602, "Invalid arguments") }
                text = try notes.read(filename)
            default: return error(-32602, "Unknown tool or invalid arguments")
            }
            result = ["content": [["type": "text", "text": text]]]
        } catch {
            result = ["isError": true, "content": [["type": "text", "text": "노트를 읽을 수 없습니다."]]]
        }
    default: return error(-32601, "Method not found")
    }
    return ["jsonrpc": "2.0", "id": id, "result": result]
}

guard CommandLine.arguments.count == 2 else { exit(EX_USAGE) }
let notes = try NoteDirectory(path: CommandLine.arguments[1])
while let line = readLine() {
    if let response = reply(line, notes: notes) {
        var data = try JSONSerialization.data(withJSONObject: response)
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
