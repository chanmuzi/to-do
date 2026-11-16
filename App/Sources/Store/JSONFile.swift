import Foundation

/// 작은 상태 값을 JSON 파일 하나로 읽고 쓴다.
struct JSONFile<Value: Codable> {
    let url: URL

    /// 파일이 없으면 `nil`.
    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
