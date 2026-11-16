import Foundation
import Models

public enum StoreError: Error, Equatable, CustomStringConvertible {
    case noteNotFound(NoteID)
    /// 같은 식별자의 노트가 이미 있다.
    case noteAlreadyExists(NoteID)
    /// 파일이 UTF-8 글이 아니다.
    case unreadableFile(URL)

    public var description: String {
        switch self {
        case .noteNotFound(let id): "노트를 찾지 못했습니다: \(id)"
        case .noteAlreadyExists(let id): "같은 노트가 이미 있습니다: \(id)"
        case .unreadableFile(let url): "파일을 읽지 못했습니다(UTF-8 아님): \(url.path)"
        }
    }
}
