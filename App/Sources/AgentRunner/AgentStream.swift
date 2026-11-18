import Foundation

public struct AgentUsage: Codable, Equatable, Sendable {
    /// Claude에서는 캐시 읽기와 생성도 포함한다. Codex input_tokens에는 캐시가 이미 들어 있다.
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let costUSD: Double?
}

public enum AgentEvent: Equatable, Sendable {
    case started(model: String?)
    case text(String)
    case tool(String)
    case rateLimit(status: String, resetsAt: Double?)
    case usage(AgentUsage)
}

struct AgentStream {
    typealias Object = [String: Any]
    static let tools = ["list_notes", "read_note"]
    static let claudeTools = tools.map { "mcp__float__" + $0 }

    let provider: AgentProvider
    var started = false
    var completed = false
    var model: String?
    var response = ""
    var usage = AgentUsage(inputTokens: nil, outputTokens: nil, costUSD: nil)

    mutating func accept(_ data: Data, emit: (AgentEvent) -> Void) throws {
        guard let row = try? JSONSerialization.jsonObject(with: data) as? Object,
              let type = row["type"] as? String else { throw AgentError.invalidOutput }
        switch provider {
        case .claude: try claude(type, row, emit)
        case .codex: try codex(type, row, emit)
        }
    }

    private mutating func claude(_ type: String, _ row: Object, _ emit: (AgentEvent) -> Void) throws {
        if type == "system", row["subtype"] as? String == "init" {
            guard !started else { throw AgentError.isolation("init") }
            guard let tools = row["tools"] as? [String], tools.sorted() == Self.claudeTools.sorted()
            else { throw AgentError.isolation("tools") }
            guard let servers = row["mcp_servers"] as? [Object], servers.count == 1,
                  servers[0]["name"] as? String == "float", servers[0]["status"] as? String == "connected"
            else { throw AgentError.isolation("mcp_servers") }
            guard let plugins = row["plugins"] as? [Object], plugins.allSatisfy({
                ($0["name"] as? String)?.hasPrefix("cc-plugin-") == true && $0["path"] as? String == "builtin"
            }) else { throw AgentError.isolation("plugins") }
            for key in ["skills", "slash_commands"] where (row[key] as? [String])?.isEmpty != true {
                throw AgentError.isolation(key)
            }
            guard let actual = row["model"] as? String, !actual.isEmpty else { throw AgentError.invalidOutput }
            started = true
            model = actual
            emit(.started(model: actual))
            return
        }
        guard started else { throw AgentError.isolation("init") }
        switch type {
        case "stream_event":
            if let event = row["event"] as? Object, let delta = event["delta"] as? Object,
               delta["type"] as? String == "text_delta", let text = delta["text"] as? String { emit(.text(text)) }
        case "assistant":
            let message = row["message"] as? Object
            for block in message?["content"] as? [Object] ?? [] where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String, Self.claudeTools.contains(name)
                else { throw AgentError.isolation("tool_use") }
                emit(.tool(name))
            }
        case "rate_limit_event":
            if let info = row["rate_limit_info"] as? Object, let status = info["status"] as? String {
                emit(.rateLimit(status: status, resetsAt: info["resetsAt"] as? Double))
            }
        case "result":
            let counts = row["usage"] as? Object
            let input = (counts?["input_tokens"] as? Int).map {
                $0 + (counts?["cache_read_input_tokens"] as? Int ?? 0) + (counts?["cache_creation_input_tokens"] as? Int ?? 0)
            }
            usage = AgentUsage(inputTokens: input, outputTokens: counts?["output_tokens"] as? Int, costUSD: row["total_cost_usd"] as? Double)
            emit(.usage(usage))
            guard row["is_error"] as? Bool == false, row["subtype"] as? String == "success"
            else { throw AgentError.providerFailure }
            guard let result = row["result"] as? String else { throw AgentError.invalidOutput }
            response = result
            completed = true
        default: break
        }
    }

    private mutating func codex(_ type: String, _ row: Object, _ emit: (AgentEvent) -> Void) throws {
        if type == "error" || type == "turn.failed" { throw AgentError.providerFailure }
        if type == "thread.started" {
            guard !started else { throw AgentError.invalidOutput }
            started = true
            model = row["model"] as? String
            emit(.started(model: model))
            return
        }
        guard started else { throw AgentError.invalidOutput }
        switch type {
        case "turn.started":
            if let actual = row["model"] as? String { model = actual }
        case "item.started", "item.updated", "item.completed":
            guard let item = row["item"] as? Object, let kind = item["type"] as? String else { throw AgentError.invalidOutput }
            switch kind {
            case "mcp_tool_call":
                guard item["server"] as? String == "float", let name = item["tool"] as? String, Self.tools.contains(name)
                else { throw AgentError.isolation("mcp_tool_call") }
                if type == "item.started" { emit(.tool(name)) }
            case "agent_message":
                if type == "item.completed", let text = item["text"] as? String {
                    response = text
                    emit(.text(text))
                }
            case "reasoning", "todo_list": break
            default: throw AgentError.isolation("item.type")
            }
        case "turn.completed":
            let counts = row["usage"] as? Object
            usage = AgentUsage(inputTokens: counts?["input_tokens"] as? Int, outputTokens: counts?["output_tokens"] as? Int, costUSD: nil)
            emit(.usage(usage))
            completed = true
        default: break
        }
    }
}
