import AppKit
import Foundation
import Models
import Routing
import Store
import Theme
@_spi(Verification) @testable import Browse

/// 시험에 쓰는 고정된 달력과 시각: 서울 시간 2026년 11월 16일 월요일 14:00.
nonisolated enum TestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    static let now = date(11, 16, 14, 0)
}

/// 화면 없이 목록을 만들어 볼 때 쓰는 노트.
nonisolated enum Sample {
    static let work = SpaceID(rawValue: "work")
    static let home = SpaceID(rawValue: "home")

    static func note(
        _ id: String, title: String = "", body: String = "", space: SpaceID? = nil,
        color: String? = nil, reminder: Date? = nil
    ) -> BrowseIndexedNote {
        BrowseIndexedNote(Note(
            id: NoteID(rawValue: id), title: title, body: body, spaceID: space,
            colorID: color.map(PaletteID.init(rawValue:)), reminder: reminder,
            created: TestClock.now, modified: TestClock.now
        ))
    }

    /// 화면 9의 노트들. 최근에 고친 것이 앞이다.
    static let notes: [BrowseIndexedNote] = [
        note("today", title: "오늘 할 일", body: "[ ] PR #482 리뷰\n[ ] 배포 체크리스트 확인\n", space: work,
             reminder: TestClock.date(11, 16, 14, 12)),
        note("home", title: "개인", body: "[ ] 치과 예약 전화\n[ ] 택배 반품 신청\n", space: home, color: "tint-5"),
        note("scratch", title: "스크래치", body: "아이디어: 플로팅 창 투명도를\n", color: "tint-1"),
        note("release", title: "릴리즈 노트 초안", body: "2.3 변경 사항 정리\n- 배포 순서 확인\n", space: work,
             reminder: TestClock.date(11, 17, 10, 0)),
        note("untitled", title: "", body: "주말 장보기 목록\n", space: home),
        note("meeting", title: "회의 메모 11-13", body: "디자인 싱크, 다음 주 일정\n", space: work),
        note("api", title: "API Notes", body: "Rate limit and **Retry** policy\n", space: work),
    ]

    static let floating = ["today", "home", "scratch"].map(NoteID.init(rawValue:))
}

extension BrowseEntry {
    /// 시험에서 견주기 쉬운 짧은 이름.
    var label: String {
        switch self {
        case .header(let title): "# \(title)"
        case .note(let row): row.id.rawValue
        case .create(let query): "+ \(query)"
        case .separator: "---"
        case .library: "library"
        }
    }
}

/// 임시 폴더의 저장소와 테마로 노트 찾기를 실제로 만들어 보는 시험용 조립.
@MainActor
final class BrowseFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("browse-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let spaces: SpaceStore
    let windowStates: WindowStateStore
    private(set) var routes: [Route] = []
    private(set) var logs: [String] = []

    init() throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        location = .isolated(notesDirectory: root)
        theme = try Theme.bundled()
        notes = try FileNoteStore(location: location, autosaveDelay: .seconds(60), autosaveMaxWait: .seconds(120))
        spaces = try SpaceStore(location: location)
        windowStates = try WindowStateStore(location: location)
        try spaces.replace(with: [
            Space(id: Sample.work, name: "회사", icon: .symbol(name: "briefcase", colorID: nil)),
            Space(id: Sample.home, name: "개인", icon: .symbol(name: "house", colorID: nil)),
        ])
    }

    /// 노트를 만든다. 나중에 만든 것이 목록의 앞에 오도록 고친 시각을 벌려 둔다.
    private var created = 0
    func add(
        _ title: String, body: String, space: SpaceID? = nil, reminder: Date? = nil, floating: Bool = false
    ) throws -> NoteID {
        let note = try notes.create(NoteDraft(title: title, body: body, spaceID: space, reminder: reminder))
        created += 1
        let url = location.notesDirectory.appendingPathComponent("\(note.id.rawValue).md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(created) * 60)],
            ofItemAtPath: url.path
        )
        try notes.refresh()
        if floating {
            try windowStates.set(NoteWindowState(isOpen: true, stackOrder: created), for: note.id)
        }
        return note.id
    }

    /// 다른 앱의 입력을 빼앗지 않게 키 창으로 만들지 않는 노트 찾기.
    func makeCoordinator() -> BrowseCoordinator {
        let coordinator = BrowseCoordinator(
            theme: theme, notes: notes, spaces: spaces,
            router: RouteDispatcher { [unowned self] in routes.append($0) },
            windowStates: windowStates,
            log: { [unowned self] in logs.append($0) }
        )
        coordinator.takesKeyOnShow = false
        coordinator.isShownOpaque = false
        coordinator.now = { TestClock.now }
        coordinator.calendar = TestClock.calendar
        return coordinator
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension NSTextView {
    /// 키보드로 친 것처럼 글자를 넣는다.
    func type(_ text: String) {
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// 한글 입력기가 조합 중인 글자를 넣는 것처럼 넣는다.
    func compose(_ text: String) {
        setMarkedText(
            text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}
