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
    public var schedules: [ScheduleItem]
    /// 옛 호출자·파일을 위한 투영. 화면에서는 displayedSchedule(at:)을 쓴다.
    public var reminder: Date? {
        get { schedules.filter { !$0.isCompleted && !$0.isDeleted }.map(\.start).min() }
        set {
            schedules = newValue.map { [ScheduleItem(id: "legacy-" + id.rawValue, start: $0, modified: $0)] } ?? []
        }
    }
    public func displayedSchedule(at now: Date, calendar: Calendar = .current) -> ScheduleItem? {
        let active = schedules.filter { !$0.isCompleted && !$0.isDeleted }.sorted { $0.start < $1.start }
        return active.first { $0.isUpcoming(at: now, calendar: calendar) } ?? active.first
    }
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
        schedules: [ScheduleItem]? = nil,
        created: Date,
        modified: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.spaceID = spaceID
        self.colorID = colorID
        self.schedules = schedules ?? reminder.map { [ScheduleItem(id: "legacy-" + id.rawValue, start: $0, modified: $0)] } ?? []
        self.created = created
        self.modified = modified
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, body, spaceID, colorID, reminder, schedules, created, modified
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(NoteID.self, forKey: .id), title: try c.decode(String.self, forKey: .title),
                  body: try c.decode(String.self, forKey: .body), spaceID: try c.decodeIfPresent(SpaceID.self, forKey: .spaceID),
                  colorID: try c.decodeIfPresent(PaletteID.self, forKey: .colorID),
                  reminder: try c.decodeIfPresent(Date.self, forKey: .reminder),
                  schedules: try c.decodeIfPresent([ScheduleItem].self, forKey: .schedules),
                  created: try c.decode(Date.self, forKey: .created), modified: try c.decode(Date.self, forKey: .modified))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(body, forKey: .body)
        try c.encodeIfPresent(spaceID, forKey: .spaceID); try c.encodeIfPresent(colorID, forKey: .colorID)
        try c.encodeIfPresent(reminder, forKey: .reminder); try c.encode(schedules, forKey: .schedules)
        try c.encode(created, forKey: .created); try c.encode(modified, forKey: .modified)
    }

}

/// 새 노트를 만들 때 넘기는 내용. 식별자와 날짜는 `Store`가 정한다.
public struct NoteDraft: Hashable, Sendable {
    public var title: String
    public var body: String
    public var spaceID: SpaceID?
    public var colorID: PaletteID?
    public var reminder: Date?
    public var schedules: [ScheduleItem]?

    public init(
        title: String = "",
        body: String = "",
        spaceID: SpaceID? = nil,
        colorID: PaletteID? = nil,
        reminder: Date? = nil,
        schedules: [ScheduleItem]? = nil
    ) {
        self.title = title
        self.body = body
        self.spaceID = spaceID
        self.colorID = colorID
        self.reminder = reminder
        self.schedules = schedules
    }
}

extension Note {
    /// 아무것도 적지 않은 노트: 제목과 본문이 비었거나 공백뿐이고 리마인더가 없다. 창을 닫거나 앱을 끝낼 때
    /// 휴지통을 거치지 않고 지운다(D-040). 스페이스와 색은 적은 것으로 치지 않는다.
    public var isBlank: Bool {
        title.allSatisfy(\.isWhitespace) && body.allSatisfy(\.isWhitespace) && schedules.isEmpty
    }
}
