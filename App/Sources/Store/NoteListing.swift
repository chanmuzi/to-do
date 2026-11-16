import Foundation
import Models

/// 폴더를 훑은 결과. 읽지 못한 파일이 있어도 나머지 노트는 돌려준다.
public struct NoteListing: Hashable, Sendable {
    /// 읽은 노트. 최근에 고친 것이 앞.
    public let notes: [Note]
    /// 읽지 못한 `.md` 항목(UTF-8이 아닌 파일, `.md`로 끝나는 폴더 등). 식별자 순.
    public let failures: [NoteReadFailure]

    public init(notes: [Note], failures: [NoteReadFailure] = []) {
        self.notes = notes
        self.failures = failures
    }
}

/// 읽지 못한 노트 파일 하나.
public struct NoteReadFailure: Hashable, Sendable {
    public let id: NoteID
    public let url: URL
    public let error: StoreError

    public init(id: NoteID, url: URL, error: StoreError) {
        self.id = id
        self.url = url
        self.error = error
    }
}
