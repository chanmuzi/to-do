import Foundation
import Models

/// 앱의 단일 작성자. 열 수 없는 기록은 원래 위치에 보존하고 다른 기록을 계속 읽는다.
@MainActor public final class AgentStore {
    private let directory: URL
    private var conversations: URL { directory.appending(path: "conversations", directoryHint: .isDirectory) }
    private var instructions: URL { directory.appending(path: "instructions.md") }

    public init(location: StoreLocation) {
        directory = location.stateDirectory.appending(path: "agent", directoryHint: .isDirectory)
    }

    public func loadConversations(warning: (String) -> Void) throws -> [AgentConversation] {
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: conversations, includingPropertiesForKeys: nil) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                let value = try JSONDecoder().decode(AgentConversation.self, from: Data(contentsOf: url))
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == value.id else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return value
            } catch {
                warning("\(url.lastPathComponent) 대화를 열지 못했습니다. \(error.localizedDescription)")
                return nil
            }
        }.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    public func save(_ value: AgentConversation) throws {
        try prepare(conversations)
        let file = try fileURL(value.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: file, options: .atomic)
    }

    private func fileURL(_ id: UUID) throws -> URL {
        let canonical = conversations.appending(path: id.uuidString.lowercased() + ".json")
        if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: conversations, includingPropertiesForKeys: nil)
            return files.first { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) == id } ?? canonical
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return canonical }
    }

    public func deleteConversation(_ id: UUID) throws {
        do { try FileManager.default.removeItem(at: fileURL(id)) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    public func readInstructions() throws -> String {
        do { return try String(contentsOf: instructions, encoding: .utf8) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return "" }
    }

    public func saveInstructions(_ value: String) throws {
        try prepare(directory)
        try value.write(to: instructions, atomically: true, encoding: .utf8)
    }

    private func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
    }
}
