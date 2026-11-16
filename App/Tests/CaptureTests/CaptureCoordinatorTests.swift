import AppKit
import Models
import Routing
import Store
import Testing
@_spi(Verification) @testable import Capture

/// 캡처 바를 실제로 띄우고 입력 경로(`insertText`, `setMarkedText`, `doCommand(by:)`)로 움직여 본다.
@MainActor
@Suite struct CaptureCoordinatorTests {
    private let fixture: CaptureFixture
    private let capture: CaptureCoordinator
    private let work = CaptureFixture.work.id
    private let home = CaptureFixture.home.id

    init() throws {
        fixture = try CaptureFixture()
        capture = fixture.makeCoordinator()
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
            // 화면 아래쪽에 뜬다(Dock 위로 영역 높이의 20%).
            #expect(window.frame.maxY < screen.visibleFrame.midY)
            #expect(window.frame.minY > screen.visibleFrame.minY)
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

    /// 한글을 조합하는 중의 ↵는 조합을 끝내기만 한다. 그다음 ↵에 넣는다.
    @Test func returnDuringCompositionCommitsInsteadOfSubmitting() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        capture.now = { note.created }
        capture.show()
        try input().type("우유 사")
        try input().compose("기")
        #expect(try input().hasMarkedText())
        #expect(try input().string == "우유 사기")
        #expect(!capture.showsPlaceholder)

        try press(returnKey)
        #expect(capture.isVisible)
        #expect(try !input().hasMarkedText())
        #expect(try input().string == "우유 사기")
        #expect(try fixture.notes.load(note.id).body.isEmpty)

        try press(returnKey)
        #expect(!capture.isVisible)
        #expect(try fixture.notes.load(note.id).body == "[ ] 우유 사기\n")
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
        #expect(capture.displayedReminder == "내일 9:00 AM")
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
        #expect(fixture.routes == [.newNote(NewNoteRequest(draft: NoteDraft(
            title: "분기 회고 금요일 3시", spaceID: home, reminder: TestClock.date(11, 20, 15, 0)
        )))])
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
}
