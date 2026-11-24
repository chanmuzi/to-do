import Foundation

public struct CodexModel: Decodable, Sendable {
    public let slug: String
    public let displayName: String
    fileprivate let visibility: String
    struct Level: Decodable, Sendable { let effort: String }
    let levels: [Level]?
    package var efforts: [String]? { levels?.map(\.effort) }
    fileprivate let priority: Int

    private enum CodingKeys: String, CodingKey {
        case slug, displayName = "display_name", visibility, priority, levels = "supported_reasoning_levels"
    }
}

extension AgentConnection {
    public func models(_ installation: AgentInstallation) async -> [CodexModel]? {
        struct Catalog: Decodable { let models: [CodexModel] }
        guard provider == .codex else { return nil }
        do {
            return try await onWorker {
                let (status, data) = try command(installation, ["debug", "models"], directory: config)
                    .capture(byteLimit: 16 * 1024 * 1024)
                guard status == 0 else { return nil }
                return try JSONDecoder().decode(Catalog.self, from: data).models
                    .filter { $0.visibility == "list" && !$0.slug.isEmpty && !$0.displayName.isEmpty }
                    .sorted { $0.priority < $1.priority }
            }
        } catch { return nil }
    }
}
