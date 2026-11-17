import AppKit
import Foundation
import Models
import Routing
import Store
import Testing
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
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("browse-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let spaces: SpaceStore
    let windowStates: WindowStateStore
    private(set) var routes: [Route] = []
    private(set) var logs: [String] = []
    /// 요청마다 받는 쪽이 돌려줄 답. 기본은 해냄.
    var routeResult: (Route) -> RouteResult = { _ in .handled }
    /// 이어져 있지 않은 것으로 칠 요청.
    var unconnectedRoutes: Set<Route> = []

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
    func makeCoordinator(notes store: (any NoteStoring)? = nil) -> BrowseCoordinator {
        let coordinator = BrowseCoordinator(
            theme: theme, notes: store ?? notes, spaces: spaces,
            router: RouteDispatcher(
                isConnected: { [unowned self] in !unconnectedRoutes.contains($0) },
                answering: { [unowned self] in
                    routes.append($0)
                    return routeResult($0)
                }
            ),
            windowStates: windowStates,
            log: { [unowned self] in logs.append($0) }
        )
        coordinator.takesKeyOnShow = false
        coordinator.isShownOpaque = false
        coordinator.now = { TestClock.now }
        coordinator.calendar = TestClock.calendar
        return coordinator
    }

    /// 임시 폴더를 지운다. 노트 찾기가 남긴 기록(읽지 못한 목록 같은 실패)이 있으면 시험이 실패한다:
    /// 실패를 기록만 하고 지나치지 않게 한다. 실패를 일부러 일으키는 시험만 `expectingLogs`를 켠다.
    func cleanUp(expectingLogs: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) {
        if !expectingLogs {
            #expect(logs.isEmpty, "노트 찾기가 실패를 기록했다: \(logs)", sourceLocation: sourceLocation)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

/// 입력기 흉내. 시스템 입력기 대신 키 입력을 받아, 실제 입력기가 하는 차례대로 텍스트 뷰를 부른다.
/// 키 입력은 메인 스레드에서만 오므로 그렇게 믿고 텍스트 뷰를 부른다(`MainActor.assumeIsolated`).
nonisolated final class FakeInputContext: NSTextInputContext, @unchecked Sendable {
    enum Behavior {
        /// 한글 두벌식: ↵를 받으면 조합 중인 글자를 `insertText`로 확정하고, 같은 키 입력에서 `insertNewline:`을 보낸다.
        case commitsThenSendsNewline
        /// 일본어, 중국어: 조합 중의 ↵는 후보를 확정하는 데 쓰고 명령을 보내지 않는다. 조합이 없을 때만 `insertNewline:`을 보낸다.
        case consumesReturnWhileComposing
    }

    private let behavior: Behavior
    private unowned let textView: NSTextView

    init(textView: NSTextView, behavior: Behavior) {
        self.textView = textView
        self.behavior = behavior
        super.init(client: textView)
    }

    override func handleEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 36 else { return false }
        let textView = textView
        let behavior = behavior
        MainActor.assumeIsolated {
            if textView.hasMarkedText() {
                let marked = (textView.string as NSString).substring(with: textView.markedRange())
                textView.insertText(marked, replacementRange: textView.markedRange())
                if behavior == .consumesReturnWhileComposing { return }
            }
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }
        return true
    }
}

/// 알림을 건 횟수와 푼 횟수를 세는 알림 센터.
nonisolated final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (added: 0, removed: 0)

    var added: Int { lock.withLock { counts.added } }
    var removed: Int { lock.withLock { counts.removed } }

    override func addObserver(
        forName name: NSNotification.Name?, object: Any?, queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol {
        lock.withLock { counts.added += 1 }
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        lock.withLock { counts.removed += 1 }
        super.removeObserver(observer)
    }
}

/// 실제 저장소를 감싸 목록 읽기를 실패하게 할 수 있는 저장소.
@MainActor
final class UnreadableListNoteStore: NoteStoring {
    private let base: any NoteStoring
    var failsListing = false
    private(set) var listCalls = 0

    init(base: any NoteStoring) {
        self.base = base
    }

    func list() throws -> NoteListing {
        listCalls += 1
        if failsListing { throw StoreError.unreadableFile(URL(fileURLWithPath: "/notes")) }
        return try base.list()
    }
    func load(_ id: NoteID) throws -> Note { try base.load(id) }
    func create(_ draft: NoteDraft) throws -> Note { try base.create(draft) }
    func update(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note { try base.update(id, mutate) }
    func scheduleUpdate(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note {
        try base.scheduleUpdate(id, mutate)
    }
    func flushPendingSaves() throws { try base.flushPendingSaves() }
    func resolveConflict(_ id: NoteID, keeping side: ConflictSide) throws -> Note {
        try base.resolveConflict(id, keeping: side)
    }
    func hasPendingChanges(_ id: NoteID) -> Bool { base.hasPendingChanges(id) }
    func discardPendingChanges(_ id: NoteID) { base.discardPendingChanges(id) }
    func moveToTrash(_ id: NoteID) throws { try base.moveToTrash(id) }
    func delete(_ id: NoteID) throws { try base.delete(id) }
    func listTrash() throws -> NoteListing { try base.listTrash() }
    func restoreFromTrash(_ id: NoteID) throws -> Note { try base.restoreFromTrash(id) }
    func refresh() throws { try base.refresh() }
    func observe(_ handler: @escaping @MainActor (StoreChange) -> Void) -> StoreObservation { base.observe(handler) }
}

extension NSTextView {
    /// ↵ 키를 실제 키 입력 경로(`keyDown`)로 보낸다. 입력기 자리에는 `FakeInputContext`가 있어야 한다.
    func pressReturnKey() throws {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ) else { throw CocoaError(.featureUnsupported) }
        keyDown(with: event)
    }

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
