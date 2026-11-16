import Foundation
import Models

/// 저장소가 던지는 오류. 저장소 API는 이 타입만 던진다.
public enum StoreError: Error, Hashable, Sendable, CustomStringConvertible {
    /// 노트 폴더에 그 노트의 파일이 없다(휴지통으로 갔거나 지워졌다).
    case noteNotFound(NoteID)
    /// 같은 식별자의 노트가 이미 있다.
    case noteAlreadyExists(NoteID)
    /// 파일을 읽지 못했다(UTF-8 글이 아니거나, 파일이 아니거나, 읽을 권한이 없다).
    case unreadableFile(URL)
    /// 디스크의 파일이 저장소가 마지막으로 읽거나 쓴 내용과 다르다. 다른 프로그램이 고친 것이다.
    /// 저장하지 않았고, 고친 내용은 저장소가 들고 있다. `resolveConflict(_:keeping:)`로 푼다.
    case conflict(NoteID)
    /// 파일을 쓰거나 옮기지 못했다.
    case writeFailed(NoteID, message: String)
    /// `flushPendingSaves()`에서 저장하지 못한 노트들. 이 노트들의 고친 내용은 저장소에 남아 있다.
    case pendingSavesFailed([SaveFailure])

    public var description: String {
        switch self {
        case .noteNotFound(let id): "노트를 찾지 못했습니다: \(id)"
        case .noteAlreadyExists(let id): "같은 노트가 이미 있습니다: \(id)"
        case .unreadableFile(let url): "파일을 읽지 못했습니다: \(url.path)"
        case .conflict(let id): "다른 프로그램이 노트 파일을 고쳐서 저장하지 않았습니다: \(id)"
        case .writeFailed(let id, let message): "노트 파일을 쓰지 못했습니다: \(id) (\(message))"
        case .pendingSavesFailed(let failures):
            "저장하지 못한 노트가 있습니다: " + failures.map { "\($0.id) (\($0.error))" }.joined(separator: ", ")
        }
    }
}

/// 저장하지 못한 노트 하나와 그 까닭.
public struct SaveFailure: Hashable, Sendable {
    public let id: NoteID
    /// 사용자에게 보여 줄 때 쓰는 노트 제목(저장하려던 값).
    public let title: String
    public let error: StoreError

    public init(id: NoteID, title: String, error: StoreError) {
        self.id = id
        self.title = title
        self.error = error
    }
}
