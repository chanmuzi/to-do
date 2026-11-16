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
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("capture-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let spaces: SpaceStore
    private(set) var routes: [Route] = []
    private(set) var logs: [String] = []

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
    func makeCoordinator() -> CaptureCoordinator {
        let coordinator = CaptureCoordinator(
            theme: theme, notes: notes, spaces: spaces,
            router: RouteDispatcher { [unowned self] in routes.append($0) },
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
