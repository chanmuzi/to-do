import Foundation

package struct ClaudeModel: Decodable, Sendable {
    package let value: String
    package let displayName: String

    private enum CodingKeys: String, CodingKey { case value, displayName, description }

    package init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        value = try fields.decode(String.self, forKey: .value)
        let name = try fields.decode(String.self, forKey: .displayName)
        let description = try? fields.decode(String.self, forKey: .description)
        let first = description?.prefix { $0 != "\u{00B7}" }.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first, !name.isEmpty, first.hasPrefix(name) {
            displayName = first
        } else {
            displayName = name
        }
    }
}

private struct InitializationMessage: Decodable {
    struct Reply: Decodable {
        struct Payload: Decodable { let models: [ClaudeModel] }
        let request_id: String
        let subtype: String
        let response: Payload?
    }
    let type: String
    let response: Reply?
}

extension AgentConnection {
    /// SDK의 초기화 제어 요청 한 줄만 보낸다. 대화 턴과 노트 도구는 열지 않는다.
    package func claudeModels(_ installation: AgentInstallation) async -> [ClaudeModel]? {
        guard provider == .claude else { return nil }
        return try? await onWorker {
            let args = ["-p", "--setting-sources", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                        "--tools", "", "--disable-slash-commands", "--permission-mode", "dontAsk",
                        "--no-session-persistence", "--output-format", "stream-json", "--verbose", "--input-format", "stream-json"]
            let command = try command(installation, args, directory: config)
            let id = UUID().uuidString
            let request = #"{"type":"control_request","request_id":"\#(id)","request":{"subtype":"initialize"}}"#
            let input = Pipe()
            try input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))
            var catalog: [ClaudeModel]?
            let status = try command.execute(timeout: .seconds(10), standardInput: input.fileHandleForReading) { data in
                let message = try JSONDecoder().decode(InitializationMessage.self, from: data)
                if message.type == "system" { return }
                guard catalog == nil, message.type == "control_response", let reply = message.response,
                      reply.request_id == id, reply.subtype == "success", let models = reply.response?.models,
                      models.allSatisfy({ !$0.value.isEmpty && !$0.displayName.isEmpty }) else { throw AgentError.invalidOutput }
                catalog = models.filter { $0.value != "default" && $0.value != "auto" }
                try input.fileHandleForWriting.close()
            }
            guard status == 0, let catalog else { throw AgentError.invalidOutput }
            return catalog
        }
    }
}
