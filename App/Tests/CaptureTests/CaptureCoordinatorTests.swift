import AppKit
import Models
import Routing
import Store
import Testing
import FieldTestSupport
@_spi(Verification) @testable import Capture

/// 캡처 바를 실제로 띄우고 입력 경로(`insertText`, `setMarkedText`, `doCommand(by:)`)로 움직여 본다.
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@MainActor
@Suite(.serialized) struct CaptureCoordinatorTests {
    private let fixture: CaptureFixture
    private let capture: CaptureCoordinator
    private let work = CaptureFixture.work.id
    private let home = CaptureFixture.home.id

    init() throws {
        fixture = try CaptureFixture()
        capture = fixture.makeCoordinator()
    }

    @Test func captureFieldGeometry() throws {
        defer { fixture.cleanUp() }
        capture.show()
        let root = try #require(capture.window?.contentView)
        try FieldGeometry.verify(#require(FieldGeometry.fields(in: root).first))
    }

    private func input() throws -> NSTextView {
        try #require(capture.inputView)
    }

    private func press(_ selector: Selector) throws {
        try input().doCommand(by: selector)
    }

    private let returnKey = #selector(NSResponder.insertNewline(_:))
    private let tabKey = #selector(NSResponder.insertTab(_:))
    private let backtabKey = #selector(NSResponder.insertBacktab(_:))
    private let escapeKey = #selector(NSResponder.cancelOperation(_:))

    @Test func showsAsAnEmptyBarOfTheSpecSizeWithTheFirstSpace() throws {
        defer { fixture.cleanUp() }
        #expect(!capture.isVisible)
        capture.show()
        #expect(capture.isVisible)
        let window = try #require(capture.window)
        #expect(window.frame.size == NSSize(width: 580, height: 42))
        #expect(window.canBecomeKey)
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.firstResponder === capture.inputView)
        // 빈 바에는 자리 글자만 있다. 스페이스는 글을 적기 시작하면 보인다.
        #expect(capture.showsPlaceholder)
        #expect(capture.displayedSpace == nil)
        #expect(capture.displayedReminder == nil)
        try input().type("우")
        #expect(capture.displayedSpace == "회사")
        if let screen = window.screen {
            #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
            // 화면 아래쪽에 뜬다(Dock 위로 영역 높이의 10%, D-156).
            #expect(window.frame.maxY < screen.visibleFrame.midY)
            #expect(window.frame.minY > screen.visibleFrame.minY)
            // 나타나는 중이면 아직 `capture-rise`(6)만큼 아래에서 올라오는 중일 수 있다.
            let lift = window.frame.minY - screen.visibleFrame.minY
            let resting = (screen.visibleFrame.height * 0.1).rounded()
            #expect(lift >= resting - 6 - 1 && lift <= resting + 1)
        }
    }

    @Test func typingATimeShowsTheReminderAndUnderlinesIt() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("릴리즈 노트 초안 쓰기 내일 오전 10시")
        #expect(!capture.showsPlaceholder)
        #expect(capture.displayedReminder == "내일 10:00 AM")
        #expect(capture.underlinedRange == NSRange(location: 13, length: 9))
        // 밑줄은 글 저장소가 아니라 배치 쪽의 임시 속성이다.
        let storage = try #require(try input().textStorage)
        #expect(storage.attribute(.underlineStyle, at: 14, effectiveRange: nil) == nil)
        let layout = try #require(try input().layoutManager)
        #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 14, effectiveRange: nil) != nil)
        #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 12, effectiveRange: nil) == nil)

        // 시간 표현을 지우면 표시와 밑줄도 사라진다.
        try input().setSelectedRange(NSRange(location: 12, length: 10))
        try press(#selector(NSResponder.deleteBackward(_:)))
        #expect(try input().string == "릴리즈 노트 초안 쓰기")
        #expect(capture.displayedReminder == nil)
        #expect(capture.underlinedRange == nil)
    }

    @Test func returnAppendsToTodaysNoteAndCloses() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘 할 일", body: "[ ] PR 리뷰\n", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try input().type("배포 체크리스트 확인")
        try press(returnKey)

        #expect(!capture.isVisible)
        #expect(try fixture.fileText(note.id).hasSuffix("---\n[ ] PR 리뷰\n[ ] 배포 체크리스트 확인\n"))
        #expect(fixture.routes.isEmpty)
        // 다시 열면 비어 있다.
        capture.show()
        #expect(try input().string.isEmpty)
        #expect(capture.showsPlaceholder)
    }

    @Test func returnOnEmptyTextDoesNothing() throws {
        defer { fixture.cleanUp() }
        capture.show()
        try press(returnKey)
        try input().type("   ")
        try press(returnKey)
        #expect(capture.isVisible)
        #expect(try fixture.notes.list().notes.isEmpty)
    }

    private func useInputMethod(_ behavior: FakeInputContext.Behavior) throws {
        let view = try #require(capture.inputView as? CaptureTextView)
        view.inputContextOverride = FakeInputContext(textView: view, behavior: behavior)
    }

    /// 한글 두벌식: 마지막 글자가 조합 중일 때 ↵를 한 번 누르면, 입력기가 그 글자를 확정하고 같은 키 입력에서
    /// 줄바꿈 명령을 보낸다. 그 한 번으로 다 확정된 글이 들어간다(↵를 두 번 누르게 하지 않는다).
    @Test func oneReturnSubmitsTheCommittedTextWithAKoreanInputMethod() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try useInputMethod(.commitsThenSendsNewline)
        try input().type("우유 사")
        try input().compose("기")
        #expect(try input().hasMarkedText())
        #expect(try input().string == "우유 사기")
        #expect(!capture.showsPlaceholder)

        try input().pressReturnKey()

        #expect(!capture.isVisible)
        #expect(try fixture.notes.load(note.id).body == "[ ] 우유 사기\n")
    }

    /// 조합 중이 아닐 때의 ↵도 같은 키 입력 경로로 한 번에 들어간다.
    @Test func returnKeyWithoutCompositionSubmits() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try useInputMethod(.commitsThenSendsNewline)
        try input().type("우유 사기")
        try input().pressReturnKey()
        #expect(!capture.isVisible)
        #expect(try fixture.notes.load(note.id).body == "[ ] 우유 사기\n")
    }

    /// 일본어, 중국어 입력기: 조합 중의 ↵는 입력기가 후보를 확정하는 데 쓰고 명령을 보내지 않는다. 넣지 않는다.
    /// 그다음 ↵에 넣는다.
    @Test func returnConsumedByTheInputMethodDoesNotSubmit() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try useInputMethod(.consumesReturnWhileComposing)
        try input().compose("牛乳")
        try input().pressReturnKey()
        #expect(capture.isVisible)
        #expect(try !input().hasMarkedText())
        #expect(try input().string == "牛乳")
        #expect(try fixture.notes.load(note.id).body.isEmpty)

        try input().pressReturnKey()
        #expect(!capture.isVisible)
        #expect(try fixture.notes.load(note.id).body == "[ ] 牛乳\n")
    }

    /// 줄바꿈 명령이 왔는데 조합 중인 글자가 남아 있으면(입력기가 확정하지 않고 명령만 보냄) 조합을 끝내기만 한다.
    @Test func newlineCommandWhileStillComposingOnlyEndsTheComposition() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try input().type("우유 사")
        try input().compose("기")

        try press(returnKey)
        #expect(capture.isVisible)
        #expect(try !input().hasMarkedText())
        #expect(try input().string == "우유 사기")
        #expect(try fixture.notes.load(note.id).body.isEmpty)
    }

    // MARK: - 읽은 때 보여 주기

    /// 떨어뜨려 적은 날과 시각은 둘 다 밑줄이 그어지고 하나의 리마인더로 보인다.
    @Test func separatedDateAndTimeAreBothUnderlined() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("내일 회의 3시")
        #expect(capture.displayedReminder == "내일 3:00 PM")
        #expect(capture.underlinedRanges == [NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)])
        let layout = try #require(try input().layoutManager)
        #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 0, effectiveRange: nil) != nil)
        #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 3, effectiveRange: nil) == nil)
        #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 6, effectiveRange: nil) != nil)
        #expect(!capture.displaysReminderAsPast)
    }

    /// 오전, 오후를 적지 않아 고른 시각도 오전, 오후를 붙여 보여 준다. 내일로 넘어갔으면 날도 보인다.
    @Test func resolvedReadingIsShownWithDayAndMeridiem() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("9시 스탠드업")
        #expect(capture.displayedReminder == "내일 9:00 AM")
        try input().selectAll(nil)
        try input().type("3시 회의")
        #expect(capture.displayedReminder == "3:00 PM")
        try input().selectAll(nil)
        try input().type("내년 12월 1일 정산")
        #expect(capture.displayedReminder == "2027/12/1")
    }

    /// 지난 때로 읽힌 표현은 지난 모습으로 보이고, 항목은 넣되 리마인더는 걸지 않는다.
    @Test func pastTimeIsShownStruckOutAndNotWrittenAsAReminder() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        // 그날 23:59. "오늘 09:00"은 언제 돌려도 지난 때다.
        let lateToday = try #require(Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: note.created))
        capture.now = { max(lateToday, note.created) }
        capture.show()
        try input().type("오늘 09:00 스탠드업")
        #expect(capture.displayedReminder == "9:00 AM")
        #expect(capture.displaysReminderAsPast)
        #expect(capture.underlinedRange == NSRange(location: 0, length: 8))

        try press(returnKey)
        #expect(!capture.isVisible)
        let saved = try fixture.notes.load(note.id)
        #expect(saved.body == "[ ] 오늘 09:00 스탠드업\n")
        #expect(saved.reminder == nil)
        #expect(fixture.logs.contains { $0.contains("리마인더는 걸지 않았습니다") })

        // 지나지 않은 때는 보통 모습이다.
        capture.show()
        try input().type("내일 09:00 스탠드업")
        #expect(!capture.displaysReminderAsPast)
    }

    /// ⌘↵로 새 노트를 만들 때도 지난 때는 리마인더로 넘기지 않는다.
    @Test func pastTimeIsNotRoutedAsAReminder() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("오늘 09:00 회고")
        capture.performSubmitAsNewNote()
        #expect(fixture.routes == [.newNote(NewNoteRequest(draft: NoteDraft(
            title: "오늘 09:00 회고", spaceID: work, reminder: nil
        )))])
    }

    // MARK: - 풀리지 않은 문제가 있는 노트

    /// 오늘 노트가 충돌 중이면 줄을 그 노트의 "쓰지 못한 변경"에 얹어 두고 닫지 않는다. 새 노트를 만들어 넣고 까닭을 남긴다.
    @Test func conflictedTodayNoteSendsTheLineToANewNote() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음\n", spaceID: work))
        try fixture.notes.scheduleUpdate(note.id) { $0.body = "처음\n편집 중\n" }
        let url = fixture.location.notesDirectory.appendingPathComponent("\(note.id.rawValue).md")
        let external = try fixture.fileText(note.id).replacingOccurrences(of: "처음\n", with: "밖에서 바꿈\n")
        try external.write(to: url, atomically: true, encoding: .utf8)
        capture.now = { note.created }
        capture.show()
        try input().type("캡처한 일")
        try press(returnKey)

        #expect(!capture.isVisible)
        let others = try fixture.notes.list().notes.filter { $0.id != note.id }
        let created = try #require(others.first)
        #expect(others.count == 1)
        #expect(created.title == CaptureDestination.title(for: note.created, calendar: .current))
        #expect(try fixture.fileText(created.id).hasSuffix("---\n[ ] 캡처한 일\n"))
        // 충돌 중인 노트는 디스크도, 쓰지 못한 변경도 그대로다.
        #expect(try fixture.fileText(note.id) == external)
        #expect(try fixture.notes.load(note.id).body == "처음\n편집 중\n")
        #expect(fixture.logs.contains { $0.contains("풀리지 않은 문제") && $0.contains(note.id.rawValue) })
    }

    // MARK: - 나타나고 사라질 때

    /// 조금 아래에서 올라오며 나타나고, 그리로 내려가며 사라진다(`capture-rise`).
    @Test func barRisesInAndSinksOut() async throws {
        defer { fixture.cleanUp() }
        capture.show()
        let window = try #require(capture.window)
        let settled = capture.settledFrame
        #expect(capture.entranceFrame == settled.offsetBy(dx: 0, dy: -fixture.theme.component(.captureRise)))
        #expect(fixture.theme.component(.captureRise) > 0)
        // 움직임이 있을 때는 아래에서 시작한다("동작 줄이기"가 켜져 있으면 바로 제자리다).
        if CaptureStyle(theme: fixture.theme).transitionDuration > 0 {
            #expect(window.frame == capture.entranceFrame)
        }
        var deadline = Date().addingTimeInterval(3)
        while window.frame != settled, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(window.frame == settled)
        // 크기는 그대로다: 안의 요소가 밀리지 않는다.
        #expect(window.frame.size == capture.entranceFrame.size)

        capture.hide()
        deadline = Date().addingTimeInterval(3)
        while window.isVisible, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!window.isVisible)
        #expect(window.frame == capture.entranceFrame)
    }

    /// 걸어 둔 알림은 캡처 바가 없어질 때 모두 푼다.
    @Test func observersAreRemovedWhenTheCoordinatorGoesAway() throws {
        defer { fixture.cleanUp() }
        let center = CountingNotificationCenter()
        var coordinator: CaptureCoordinator? = fixture.makeCoordinator()
        coordinator?.notificationCenter = center
        coordinator?.show()
        #expect(center.added == 2)
        #expect(center.removed == 0)
        // 다시 띄워도 더 걸지 않는다.
        coordinator?.show()
        #expect(center.added == 2)
        coordinator?.window?.orderOut(nil)
        weak let released = coordinator
        coordinator = nil
        #expect(released == nil)
        #expect(center.removed == 2)
    }

    /// 조합 중에도 시간 표현을 읽지만 조합은 끊기지 않는다.
    @Test func parsingWhileComposingKeepsTheComposition() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("회의 내일 10")
        try input().compose("시")
        #expect(capture.displayedReminder == "내일 10:00 AM")
        #expect(try input().hasMarkedText())
        #expect(try input().markedRange() == NSRange(location: 8, length: 1))
        // 조합이 이어진다: 같은 자리의 글자가 바뀐다.
        try input().compose("십")
        #expect(try input().string == "회의 내일 10십")
        // 시각이 없어졌다. 날만 남아 오전 9시로 읽힌다.
        #expect(capture.displayedReminder == "내일")
        #expect(capture.underlinedRange == NSRange(location: 3, length: 2))
    }

    @Test func tabCyclesTheSpaceAndItIsRememberedAfterAdding() throws {
        defer { fixture.cleanUp() }
        capture.show()
        #expect(capture.displayedSpace == nil)
        try press(tabKey)
        #expect(capture.displayedSpace == "개인")
        try press(tabKey)
        #expect(capture.displayedSpace == nil)
        try press(tabKey)
        #expect(capture.displayedSpace == "회사")
        try press(backtabKey)
        try press(backtabKey)
        #expect(capture.displayedSpace == "개인")
        #expect(try input().string.isEmpty)

        try input().type("치과 예약")
        try press(returnKey)
        let created = try #require(try fixture.notes.list().notes.first)
        #expect(created.spaceID == home)
        #expect(created.body == "[ ] 치과 예약\n")

        capture.show()
        #expect(capture.displayedSpace == nil)
        try input().type("택배")
        #expect(capture.displayedSpace == "개인")
    }

    @Test func spaceTokenInTheTextOverridesTheSelection() throws {
        defer { fixture.cleanUp() }
        capture.show()
        try input().type("#개인 장보기")
        #expect(capture.displayedSpace == "개인")
        try press(returnKey)
        let created = try #require(try fixture.notes.list().notes.first)
        #expect(created.spaceID == home)
        #expect(created.body == "[ ] 장보기\n")
    }

    @Test func commandRCyclesAManualReminder() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try input().type("내일 10시 회의")
        #expect(capture.displayedReminder == "내일 10:00 AM")
        capture.performCycleReminder()
        #expect(capture.displayedReminder == "3:00 PM")
        #expect(capture.underlinedRange == nil)
        capture.performCycleReminder()
        #expect(capture.displayedReminder == "6:00 PM")
        capture.performCycleReminder()
        capture.performCycleReminder()
        #expect(capture.displayedReminder == "11/23 9:00 AM")
        // 한 바퀴 돌면 글에서 읽은 시간으로 돌아간다.
        capture.performCycleReminder()
        #expect(capture.displayedReminder == "내일 10:00 AM")
        #expect(capture.underlinedRange == NSRange(location: 0, length: 6))
    }

    @Test func commandReturnRoutesANewNoteAndCloses() throws {
        defer { fixture.cleanUp() }
        capture.now = { TestClock.now }
        capture.calendar = TestClock.calendar
        capture.show()
        try press(tabKey)
        try input().type("분기 회고 금요일 3시")
        capture.performSubmitAsNewNote()

        #expect(!capture.isVisible)
        #expect(fixture.routes.count == 1)
        guard case .newNote(let request) = fixture.routes.first else { Issue.record("새 노트 요청 없음"); return }
        #expect(request.draft.title == "분기 회고 금요일 3시")
        #expect(request.draft.spaceID == home)
        #expect(request.draft.schedules?.first?.start == TestClock.date(11, 20, 15, 0))
        #expect(request.draft.schedules?.first?.todo == nil)
        // 캡처 바가 직접 노트를 만들지 않는다.
        #expect(try fixture.notes.list().notes.isEmpty)
    }

    @Test func escapeClosesWithoutAdding() throws {
        defer { fixture.cleanUp() }
        capture.show()
        try input().type("버릴 글")
        try press(escapeKey)
        #expect(!capture.isVisible)
        #expect(try fixture.notes.list().notes.isEmpty)
        #expect(fixture.routes.isEmpty)
    }

    // MARK: - 닫힘과 실패를 알리기

    /// 닫힐 때 포커스를 열기 전의 자리로 돌려줄지 알린다: esc, ↵로 넣음, `hide()`는 돌려주고,
    /// ⌘↵는 새 노트가 키 창이 되므로 돌려주지 않는다. ⌘↵는 새 노트가 만들어진 뒤에 닫히므로 알림이 요청 뒤에 온다.
    @Test func dismissalTellsWhetherFocusShouldGoBack() throws {
        defer { fixture.cleanUp() }
        var events: [String] = []
        capture.onDismiss = { [fixture] in events.append("dismiss \($0) routes \(fixture.routes.count)") }

        capture.show()
        try press(escapeKey)
        capture.show()
        try input().type("우유 사기")
        capture.performSubmit()
        capture.show()
        capture.hide()
        // 이미 닫히는 중이면 다시 알리지 않는다.
        capture.hide()
        capture.show()
        try input().type("새 노트로")
        capture.performSubmitAsNewNote()

        #expect(events == [
            "dismiss true routes 0", "dismiss true routes 0", "dismiss true routes 0", "dismiss false routes 1",
        ])
        #expect(fixture.routes.count == 1)
    }

    /// 넣지 못하면 기록만 하지 않고 App에 알린다. 바는 적은 글을 그대로 둔 채 열려 있고, 닫혔다고 알리지 않는다.
    @Test func failedSubmitIsReportedAndTheBarStaysOpenWithItsText() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", spaceID: work))
        let store = FaultyNoteStore(base: fixture.notes)
        store.faults = [note.id: .writeFailed(note.id, message: "쓸 수 없음")]
        let capture = fixture.makeCoordinator(notes: store)
        var failures: [Error] = []
        var dismissals = 0
        capture.onFailure = { failures.append($0) }
        capture.onDismiss = { _ in dismissals += 1 }

        capture.show()
        let input = try #require(capture.inputView)
        input.type("우유 사기")
        capture.performSubmit()

        #expect(failures.count == 1)
        #expect(failures.first as? StoreError == .writeFailed(note.id, message: "쓸 수 없음"))
        #expect(fixture.logs.contains { $0.contains("넣지 못했습니다") })
        #expect(capture.isVisible)
        #expect(input.string == "우유 사기")
        #expect(dismissals == 0)

        // 문제가 풀린 뒤 다시 ↵를 누르면 들어가고 닫힌다.
        store.faults = [:]
        capture.performSubmit()
        #expect(failures.count == 1)
        #expect(!capture.isVisible)
        #expect(try fixture.fileText(note.id).hasSuffix("[ ] 우유 사기\n"))
    }

    @Test func toggleShowsAndHides() async throws {
        defer { fixture.cleanUp() }
        capture.toggle()
        #expect(capture.isVisible)
        capture.toggle()
        #expect(!capture.isVisible)
        // 사라지는 움직임이 끝나면 창이 내려간다.
        let window = try #require(capture.window)
        let deadline = Date().addingTimeInterval(3)
        while window.isVisible, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!window.isVisible)
        // 사라지는 중에 다시 열면 내려가지 않는다.
        capture.show()
        capture.hide()
        capture.show()
        try await Task.sleep(for: .milliseconds(400))
        #expect(capture.isVisible)
        #expect(window.isVisible)
    }

    @Test func pastedLineBreaksBecomeSpaces() throws {
        defer { fixture.cleanUp() }
        capture.show()
        try input().type("첫 줄\n둘째 줄\t끝")
        #expect(try input().string == "첫 줄 둘째 줄 끝")
    }

    // MARK: - 닫히는 중에는 명령을 받지 않는다

    /// 검토에서 나온 문제: 다른 앱에서 연 캡처 바에 글을 적고 ↵를 잇달아 두 번 누르면(사라지는 `dur` 안에)
    /// 투두가 두 번 들어갔다. 닫히기 시작한 바는 명령도 글도 받지 않는다.
    @Test func secondReturnWhileClosingAddsNothing() throws {
        defer { fixture.cleanUp() }
        capture.show()
        try input().type("우유 사기")
        try press(returnKey)
        #expect(!capture.isVisible)
        #expect(try !input().isEditable)
        // 창은 아직 내려가지 않았다(사라지는 중). 그사이의 ↵, ⌘↵, ⇥.
        try press(returnKey)
        capture.performSubmit()
        capture.performSubmitAsNewNote()
        try press(tabKey)

        let notes = try fixture.notes.list().notes
        #expect(notes.count == 1)
        #expect(try fixture.fileText(#require(notes.first).id).hasSuffix("---\n[ ] 우유 사기\n"))
        #expect(fixture.routes.isEmpty)

        // 다시 띄우면 전처럼 글을 받는다.
        capture.show()
        #expect(try input().isEditable)
        try input().type("빵 사기")
        try press(returnKey)
        #expect(try fixture.fileText(#require(notes.first).id).hasSuffix("[ ] 우유 사기\n[ ] 빵 사기\n"))
    }

    /// 창을 내리는 일은 움직임이 끝났다는 알림이 아니라 전환 시간에 걸려 있다: 화면이 꺼져 움직임이 나아가지
    /// 않아도 `dur` 뒤에는 창이 내려가 있고 끝의 자리와 알파에 놓여 있다.
    @Test func hiddenBarIsOrderedOutAfterTheTransitionTimeWhateverTheAnimationDid() async throws {
        defer { fixture.cleanUp() }
        capture.show()
        let window = try #require(capture.window)
        var deadline = Date().addingTimeInterval(3)
        while window.frame != capture.settledFrame, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(window.frame == capture.settledFrame)

        capture.hide()
        // 닫히기 시작하면 곧바로 글을 받지 않고, 창은 전환 시간 뒤에 내려간다.
        #expect(try !input().isEditable)
        deadline = Date().addingTimeInterval(3)
        while window.isVisible, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!window.isVisible)
        #expect(window.alphaValue == 0)
        #expect(window.frame == capture.entranceFrame)
        #expect(!capture.isVisible)
    }

    // MARK: - ⌘↵의 답

    /// 검토에서 나온 문제: ⌘↵로 새 노트를 만들지 못하면(쓸 수 없는 폴더) 알림은 뜨는데 바는 이미 닫히고
    /// 적은 글이 사라져 있었다. 만들어졌을 때만 닫는다.
    @Test func commandReturnKeepsTheBarAndItsTextWhenTheNoteCannotBeMade() throws {
        defer { fixture.cleanUp() }
        var dismissals: [Bool] = []
        capture.onDismiss = { dismissals.append($0) }
        fixture.routeResult = { _ in .failed }

        capture.show()
        try input().type("분기 회고")
        capture.performSubmitAsNewNote()

        #expect(fixture.routes.count == 1)
        #expect(capture.isVisible)
        #expect(try input().string == "분기 회고")
        #expect(try input().isEditable)
        #expect(dismissals.isEmpty)
        #expect(fixture.logs.contains { $0.contains("새 노트를 만들지 못해") })

        // 이어지지 않은 요청이어도 같다(닫고 아무 일도 없는 것처럼 보이지 않는다).
        fixture.routeResult = { _ in .unconnected }
        capture.performSubmitAsNewNote()
        #expect(capture.isVisible)
        #expect(try input().string == "분기 회고")

        // 문제가 풀린 뒤 다시 누르면 만들어지고 닫힌다. 새 노트가 키 창이므로 포커스를 돌려주지 않는다.
        fixture.routeResult = { _ in .handled }
        capture.performSubmitAsNewNote()
        #expect(!capture.isVisible)
        #expect(dismissals == [false])
        #expect(fixture.routes.count == 3)
    }

    /// ⌘↵의 요청이 돌아오기 전에 키 창에서 물러나도(실패 알림 창, 새로 뜬 노트) 그 때문에 닫히지 않는다.
    @Test func resigningKeyWhileTheNewNoteRequestIsOutDoesNotDismiss() throws {
        defer { fixture.cleanUp() }
        let center = NotificationCenter()
        let capture = fixture.makeCoordinator()
        capture.notificationCenter = center
        var dismissals: [Bool] = []
        capture.onDismiss = { dismissals.append($0) }
        capture.show()
        let window = try #require(capture.window)
        fixture.routeResult = { _ in
            center.post(name: NSWindow.didResignKeyNotification, object: window)
            return .failed
        }

        try #require(capture.inputView).type("분기 회고")
        capture.performSubmitAsNewNote()
        #expect(capture.isVisible)
        #expect(dismissals.isEmpty)

        // 여느 때 키 창에서 물러나면(바깥을 누름) 닫히고 포커스는 누른 곳에 둔다.
        center.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!capture.isVisible)
        #expect(dismissals == [false])
    }

    // MARK: - ⌘W

    /// ⌘W는 esc처럼 바를 닫는다(테두리 없는 창은 `performClose`를 받지 못해 경고음만 났다).
    /// 한글 입력 상태에서는 글자가 자모로 오므로 키 자리로 견준다.
    @Test func commandWClosesTheBarLikeEscape() throws {
        defer { fixture.cleanUp() }
        var dismissals: [Bool] = []
        capture.onDismiss = { dismissals.append($0) }
        for characters in ["w", "ㅈ"] {
            capture.show()
            try input().type("버릴 글")
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: capture.window?.windowNumber ?? 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 13
            ))
            #expect(try input().performKeyEquivalent(with: event))
            #expect(!capture.isVisible)
        }
        #expect(dismissals == [true, true])
        #expect(try fixture.notes.list().notes.isEmpty)
        #expect(fixture.routes.isEmpty)
    }
}
