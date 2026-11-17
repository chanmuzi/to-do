import Foundation
import Store

/// 테스트마다 새 임시 폴더를 쓰는 저장 위치.
struct TemporaryStore {
    let root: URL
    let location: StoreLocation

    init() {
        root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("store-tests-\(UUID().uuidString)", isDirectory: true)
        location = .isolated(notesDirectory: root.appendingPathComponent("notes", isDirectory: true))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    func noteFile(_ id: String) -> URL {
        location.notesDirectory.appendingPathComponent("\(id).md", isDirectory: false)
    }
}
