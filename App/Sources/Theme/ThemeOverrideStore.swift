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

    /// 읽지 못하는 파일(잘렸거나 모양이 다름)은 지우지 않고 `<이름>.corrupt`로 옮긴 뒤
    /// 빈 값과 경고를 돌려준다. 옮기지도 못하면 던진다.
    public func loadRecovering() throws -> (overrides: ThemeOverrides, warning: String?) {
        do {
            return (try load(), nil)
        } catch {
            let aside = try moveAside()
            return (ThemeOverrides(), "\(url.lastPathComponent)을 읽지 못해 기본 테마로 시작합니다. "
                + "원래 파일은 \(aside.lastPathComponent)로 옮겨 두었습니다. (\(error))")
        }
    }

    public func save(_ overrides: ThemeOverrides) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(overrides).write(to: url, options: .atomic)
    }

    private func moveAside() throws -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.lastPathComponent + ".corrupt"
        var candidate = directory.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.moveItem(at: url, to: candidate)
        return candidate
    }
}
