import Foundation

/// 노트 하나. 노트 파일(Markdown + frontmatter)에 담기는 내용 전부다.
/// 창 위치·핀·열림 상태는 여기 없고 `NoteWindowState`에 있다(D-003).
public struct Note: Identifiable, Hashable, Codable, Sendable {
    public let id: NoteID
    /// 상단 줄에 보이는 제목. 본문과 별개다.
    public var title: String
    /// 본문 Markdown 원문. 저장할 때 한 글자도 바꾸지 않는다(D-008).
    public var body: String
    public var spaceID: SpaceID?
    /// 노트 색. `nil`이면 색 없음(기본).
    public var colorID: PaletteID?
    /// 리마인더 시각. 노트당 하나(spec 20의 8번, 임시).
    public var reminder: Date?
    public let created: Date
    /// 파일의 마지막 수정 시각. `Store`가 채운다.
    public var modified: Date

    public init(
        id: NoteID,
        title: String = "",
        body: String = "",
        spaceID: SpaceID? = nil,
        colorID: PaletteID? = nil,
        reminder: Date? = nil,
        created: Date,
        modified: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.spaceID = spaceID
        self.colorID = colorID
        self.reminder = reminder
        self.created = created
        self.modified = modified
    }
}

/// 새 노트를 만들 때 넘기는 내용. 식별자와 날짜는 `Store`가 정한다.
public struct NoteDraft: Hashable, Sendable {
    public var title: String
    public var body: String
    public var spaceID: SpaceID?
    public var colorID: PaletteID?
    public var reminder: Date?

    public init(
        title: String = "",
        body: String = "",
        spaceID: SpaceID? = nil,
        colorID: PaletteID? = nil,
        reminder: Date? = nil
    ) {
        self.title = title
        self.body = body
        self.spaceID = spaceID
        self.colorID = colorID
        self.reminder = reminder
    }
}
