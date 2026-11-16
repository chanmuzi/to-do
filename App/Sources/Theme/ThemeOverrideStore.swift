import Foundation

/// 덮어쓰기 값을 JSON 파일 하나로 읽고 쓴다.
public struct ThemeOverrideStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 파일이 없으면 빈 값.
    public func load() throws -> ThemeOverrides {
        guard FileManager.default.fileExists(atPath: url.path) else { return ThemeOverrides() }
        return try JSONDecoder().decode(ThemeOverrides.self, from: Data(contentsOf: url))
    }

    public func save(_ overrides: ThemeOverrides) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(overrides).write(to: url, options: .atomic)
    }
}
