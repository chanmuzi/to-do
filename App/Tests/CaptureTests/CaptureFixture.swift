import AppKit
import Foundation
import Models
import Routing
import Store
import Theme
@_spi(Verification) @testable import Capture

/// 시험에 쓰는 고정된 달력과 시각: 서울 시간 2026년 11월 16일 월요일 14:00.
nonisolated enum TestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    static let now = date(11, 16, 14, 0)
}

/// 임시 폴더의 저장소와 테마로 캡처 바를 실제로 만들어 보는 시험용 조립.
@MainActor
final class CaptureFixture {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("capture-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let spaces: SpaceStore
    private(set) var routes: [Route] = []
    private(set) var logs: [String] = []
    /// 요청마다 받는 쪽이 돌려줄 답. 기본은 해냄.
    var routeResult: (Route) -> RouteResult = { _ in .handled }
    /// 이어져 있지 않은 것으로 칠 요청.
    var unconnectedRoutes: Set<Route> = []

    static let work = Space(id: SpaceID(rawValue: "work"), name: "회사", icon: .symbol(name: "briefcase", colorID: nil))
    static let home = Space(id: SpaceID(rawValue: "home"), name: "개인", icon: .symbol(name: "house", colorID: nil))

    init() throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        location = .isolated(notesDirectory: root)
        theme = try Theme.bundled()
        // 자동 저장은 시험이 직접 flush한다.
        notes = try FileNoteStore(location: location, autosaveDelay: .seconds(60), autosaveMaxWait: .seconds(120))
        spaces = try SpaceStore(location: location)
        try spaces.replace(with: [Self.work, Self.home])
    }

    /// 다른 앱의 입력을 빼앗지 않게 키 창으로 만들지 않는 캡처 바. 시각은 지금(노트의 만든 날짜가 실제 시각이라서).
    func makeCoordinator(notes store: (any NoteStoring)? = nil) -> CaptureCoordinator {
        let coordinator = CaptureCoordinator(
            theme: theme, notes: store ?? notes, spaces: spaces,
            router: RouteDispatcher(
                isConnected: { [unowned self] in !unconnectedRoutes.contains($0) },
                answering: { [unowned self] in
                    routes.append($0)
                    return routeResult($0)
                }
            ),
            log: { [unowned self] in logs.append($0) }
        )
        coordinator.takesKeyOnShow = false
        coordinator.isShownOpaque = false
        return coordinator
    }

    func fileText(_ id: NoteID) throws -> String {
        try String(contentsOf: location.notesDirectory.appendingPathComponent("\(id.rawValue).md"), encoding: .utf8)
    }

    func cleanUp() {
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

/// 실제 저장소를 감싸 몇몇 노트를 읽거나 쓸 때 정해 둔 오류를 낸다(목록에는 그대로 보인다).
/// 파일이 없어진 노트, 쓰지 못하는 노트를 흉내 낸다.
@MainActor
final class FaultyNoteStore: NoteStoring {
    private let base: any NoteStoring
    var faults: [NoteID: StoreError] = [:]

    init(base: any NoteStoring) {
        self.base = base
    }

    private func check(_ id: NoteID) throws {
        if let fault = faults[id] { throw fault }
    }

    func list() throws -> NoteListing { try base.list() }
    func load(_ id: NoteID) throws -> Note {
        try check(id)
        return try base.load(id)
    }
    func create(_ draft: NoteDraft) throws -> Note { try base.create(draft) }
    func update(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note {
        try check(id)
        return try base.update(id, mutate)
    }
    func scheduleUpdate(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note {
        try check(id)
        return try base.scheduleUpdate(id, mutate)
    }
    func flushPendingSaves() throws { try base.flushPendingSaves() }
    func resolveConflict(_ id: NoteID, keeping side: ConflictSide) throws -> Note {
        try base.resolveConflict(id, keeping: side)
    }
    func hasPendingChanges(_ id: NoteID) -> Bool { base.hasPendingChanges(id) }
    func discardPendingChanges(_ id: NoteID) { base.discardPendingChanges(id) }
    func moveToTrash(_ id: NoteID) throws { try base.moveToTrash(id) }
    func delete(_ id: NoteID) throws { try base.delete(id) }
    func updateTrashSchedules(_ id: NoteID, _ change: (inout [ScheduleItem]) -> Void) throws {
        try base.updateTrashSchedules(id, change)
    }
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
