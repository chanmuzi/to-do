import Foundation

/// 작은 상태 값을 JSON 파일 하나로 읽고 쓴다.
struct JSONFile<Value: Codable> {
    let url: URL

    /// 파일이 없으면 `nil`.
    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    /// 읽지 못하는 파일(잘렸거나 모양이 다름)은 지우지 않고 옆으로 옮긴 뒤 `nil`과 경고를 돌려준다.
    /// 옮기지도 못하면 던진다(그대로 두면 다음 저장이 사용자 데이터를 덮어쓴다).
    func loadRecovering() throws -> (value: Value?, warning: String?) {
        do {
            return (try load(), nil)
        } catch {
            let aside = try moveAside()
            return (nil, "\(url.lastPathComponent)을 읽지 못해 빈 상태로 시작합니다. "
                + "원래 파일은 \(aside.lastPathComponent)로 옮겨 두었습니다. (\(error))")
        }
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// `<이름>.corrupt`(이미 있으면 `.corrupt-2`, …)로 옮긴다.
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
