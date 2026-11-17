import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
@_spi(Verification) import Editor
import Foundation
import Models
@_spi(Verification) import NotePanel
import Routing
import Store
import Testing
@testable import FloatingNotes

/// 캡처 바와 노트 찾기가 한 일이 노트 창까지 닿는지: 고른 노트가 뜨고 키 창이 되는지, 새 노트가 만들어져
/// 뜨는지, 떠 있는 오늘 노트에 캡처한 줄이 그 창에 바로 보이고 그 뒤의 입력과 함께 디스크에 남는지.
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct QuickPanelResultsTests {
    private let fixture: WiringFixture
    private let returnKey = #selector(NSResponder.insertNewline(_:))

    init() throws {
        fixture = try WiringFixture()
    }

    private func type(_ text: String, into view: NSTextView?) throws {
        try #require(view).insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - 노트 찾기에서 고르기

    /// 닫혀 있던 노트를 고르면 새 창으로 뜨고 키 창이 된다. 떠 있는 노트를 고르면 그 창이 앞으로 오고 키 창이 된다.
    @Test func choosingANoteOpensOrRaisesItAndGivesItKeyFocus() throws {
        defer { fixture.cleanUp() }
        let closed = try fixture.notes.create(NoteDraft(title: "회의 메모", body: "디자인 싱크\n")).id
        let behind = try fixture.open("뒤에 있는 노트")
        let front = try fixture.open("앞에 있는 노트")
        #expect(fixture.notePanels.frontmostNoteID == front)

        fixture.router.route(.openBrowse(anchor: nil))
        try type("회의", into: fixture.browse.inputView)
        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        #expect(!fixture.browse.isVisible)
        #expect(fixture.notePanels.openNoteIDs.contains(closed))
        #expect(fixture.keyRequests(closed) == 1)
        #expect(fixture.notePanels.snapshot(of: closed)?.isVisible == true)

        fixture.router.route(.openBrowse(anchor: nil))
        try type("뒤에", into: fixture.browse.inputView)
        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        #expect(fixture.keyRequests(behind) == 1)
        #expect(fixture.notePanels.frontmostNoteID == behind)
        #expect(fixture.keyRequests(front) == 0)
        #expect(fixture.shownFailures.isEmpty)
    }

    /// 숨긴 중에 고르면 숨김이 풀리고 그 노트가 키 창이 된다.
    @Test func choosingANoteWhileNotesAreHiddenRevealsThem() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.open("숨긴 노트")
        fixture.notePanels.toggleAllHidden()

        fixture.router.route(.openBrowse(anchor: nil))
        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        #expect(!fixture.notePanels.areNotesHidden)
        #expect(fixture.keyRequests(note) == 1)
    }

    /// "“검색어” 새 노트 만들기": 검색어가 제목인 노트를 만들어 띄우고 키 창으로 만든다.
    @Test func createRowMakesAndOpensANoteTitledWithTheQuery() throws {
        defer { fixture.cleanUp() }
        let current = try fixture.open("쓰던 노트")
        fixture.pretendKey(current)

        fixture.commands.perform(.findNote)
        try type("새 계획", into: fixture.browse.inputView)
        #expect(fixture.browse.rowDescriptions.first == "*create “새 계획” 새 노트 만들기")
        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        let created = try #require(fixture.notePanels.openNoteIDs.last)
        #expect(created != current)
        #expect(try fixture.notes.load(created).title == "새 계획")
        #expect(fixture.keyRequests(created) == 1)
        #expect(fixture.keyRequests(current) == 0)
    }

    // MARK: - 캡처

    /// ⌘↵: 적은 글이 제목인 노트를 만들어 띄운다.
    @Test func captureCommandReturnCreatesAndOpensANote() throws {
        defer { fixture.cleanUp() }
        fixture.router.route(.openCapture)
        try type("분기 회고", into: fixture.capture.inputView)
        fixture.capture.performSubmitAsNewNote()

        let created = try #require(fixture.notePanels.openNoteIDs.first)
        #expect(fixture.notePanels.openNoteIDs.count == 1)
        #expect(try fixture.notes.load(created).title == "분기 회고")
        #expect(fixture.keyRequests(created) == 1)
        #expect(!fixture.capture.isVisible)
    }

    /// ↵로 넣은 줄이 떠 있는 오늘 노트의 창에 바로 보이고, 그 뒤에 그 노트에 친 글과 함께 디스크에 남는다.
    /// 커서와 접힘은 그대로다(통째로 바꿔 넣으면 커서가 끝으로 가고 접힘이 풀린다).
    @Test func captureIntoTheOpenTodayNoteShowsInItsWindowAndSurvivesLaterTyping() throws {
        defer { fixture.cleanUp() }
        let body = "+ 접어 둔 토글\n\t안쪽 줄\n쓰던 줄\n"
        // 오늘 만든 노트가 오늘 노트다(D-026).
        let today = try fixture.open("오늘", body: body)
        let adapter = try #require(fixture.editors.editor(for: today))
        let editor = adapter.editor
        editor.selectedRange = NSRange(location: 1, length: 0)
        editor.perform(.fold)
        let caret = NSRange(location: (body as NSString).range(of: "쓰던 줄").location + 2, length: 0)
        editor.selectedRange = caret
        // 아직 저장되지 않은 입력이 있는 채로 캡처한다.
        editor.textView.insertText("!", replacementRange: editor.selectedRange)
        let typedCaret = NSRange(location: caret.location + 1, length: 0)
        fixture.pretendKey(today)

        fixture.router.route(.openCapture)
        try type("우유 사기", into: fixture.capture.inputView)
        fixture.capture.performSubmit()

        // 새 노트를 만들지 않고 그 노트에 붙였고, 그 창의 편집기에 바로 보인다.
        #expect(try fixture.notes.list().notes.count == 1)
        let captured = "+ 접어 둔 토글\n\t안쪽 줄\n쓰던! 줄\n[ ] 우유 사기\n"
        #expect(editor.text == captured)
        #expect(try fixture.fileText(today).hasSuffix(captured))
        #expect(editor.selectedRange == typedCaret)
        #expect(editor.foldedLines == [0])
        // 닫히면 쓰던 노트로 키 창이 돌아온다.
        #expect(fixture.keyRequests(today) == 1)

        // 이어서 그 자리에 친다. 편집기가 옛 글로 본문을 덮어쓰지 않는다.
        editor.textView.insertText("?", replacementRange: editor.selectedRange)
        fixture.notePanels.flushPendingEdits()
        try fixture.notes.flushPendingSaves()

        let final = "+ 접어 둔 토글\n\t안쪽 줄\n쓰던!? 줄\n[ ] 우유 사기\n"
        #expect(try fixture.fileText(today).hasSuffix(final))
        #expect(editor.text == final)
        #expect(editor.foldedLines == [0])
        #expect(fixture.windowStates.state(for: today)?.foldedLines == [0])
        #expect(fixture.logLines.allSatisfy { $0.hasPrefix("캡처: 노트") })

        // 한 번 더 캡처해도 같다.
        fixture.router.route(.openCapture)
        try type("빵 사기", into: fixture.capture.inputView)
        fixture.capture.performSubmit()
        #expect(editor.text == final + "[ ] 빵 사기\n")
        #expect(try fixture.fileText(today).hasSuffix(final + "[ ] 빵 사기\n"))
        #expect(fixture.shownFailures.isEmpty)
    }

    // MARK: - 열려 있는 목록이 노트 창을 따라가는지

    /// 노트 찾기가 열려 있는 동안 노트 창이 뜨고 내려가면 "떠 있는 노트"가 따라가고, 방금 닫은 노트가
    /// "최근에 연 노트"의 맨 앞에 온다(고친 시각은 더 오래됐어도).
    @Test func openBrowseListFollowsNoteWindowsAndOrdersRecentNotesByOpenTime() async throws {
        defer { fixture.cleanUp() }
        var clock = Date(timeIntervalSince1970: 1_900_000_000)
        fixture.notePanels.now = { clock }
        // 뒤에 만든 것이 최근에 고친 것이다.
        let old = try fixture.notes.create(NoteDraft(title: "오래된 노트")).id
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: fixture.location.notesDirectory.appendingPathComponent("\(old.rawValue).md").path
        )
        try fixture.notes.refresh()
        _ = try fixture.notes.create(NoteDraft(title: "방금 고친 노트"))

        fixture.router.route(.openBrowse(anchor: nil))
        #expect(fixture.browseTitles == ["방금 고친 노트", "오래된 노트"])

        try fixture.notePanels.open(old, focus: false)
        #expect(await fixture.wait { fixture.browseTitles == ["오래된 노트(핀)", "방금 고친 노트"] })

        clock = clock.addingTimeInterval(60)
        fixture.notePanels.closeWindow(old)
        #expect(await fixture.wait { fixture.browseTitles == ["오래된 노트", "방금 고친 노트"] })
        #expect(fixture.browse.rowDescriptions.first == " header 최근에 연 노트")
    }
}
