import Foundation

/// 저장 위치 묶음.
public struct StoreLocation: Hashable, Sendable {
    /// 노트 파일(`<id>.md`)이 있는 폴더.
    public let notesDirectory: URL
    /// 휴지통. 노트 폴더 안의 `.trash/`.
    public let trashDirectory: URL
    /// 앱 로컬 상태(창 상태, 스페이스 목록, 테마 덮어쓰기)를 두는 폴더.
    public let stateDirectory: URL

    /// 노트 폴더를 바꿀 때 쓰는 환경 변수. 값이 있으면 `isolated(notesDirectory:)`와 같다.
    public static let environmentKey = "FLOATING_NOTES_DIR"

    public init(notesDirectory: URL, stateDirectory: URL) {
        self.notesDirectory = notesDirectory.standardizedFileURL
        self.trashDirectory = self.notesDirectory.appendingPathComponent(".trash", isDirectory: true)
        self.stateDirectory = stateDirectory.standardizedFileURL
    }

    /// 기본 위치. `~/Library/Application Support/FloatingNotes/` 아래 `notes/`, `state/`.
    /// 환경 변수 `FLOATING_NOTES_DIR`가 있으면 그 폴더만 쓴다.
    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> StoreLocation {
        if let path = environment[environmentKey], !path.isEmpty {
            return isolated(notesDirectory: URL(fileURLWithPath: path, isDirectory: true))
        }
        let root = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FloatingNotes", isDirectory: true)
        return StoreLocation(
            notesDirectory: root.appendingPathComponent("notes", isDirectory: true),
            stateDirectory: root.appendingPathComponent("state", isDirectory: true)
        )
    }

    /// 한 폴더 안에서만 읽고 쓰는 위치(상태는 그 안의 `.state/`). 테스트와 확인용 실행에 쓴다.
    public static func isolated(notesDirectory: URL) -> StoreLocation {
        StoreLocation(
            notesDirectory: notesDirectory,
            stateDirectory: notesDirectory.appendingPathComponent(".state", isDirectory: true)
        )
    }
}
