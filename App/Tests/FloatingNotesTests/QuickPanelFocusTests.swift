import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Foundation
import Models
import Routing
import Testing
@testable import FloatingNotes

/// 캡처 바, 노트 찾기와 노트 창 사이의 키 입력 규칙(D-032): 닫히면 열기 전에 키 창이던 노트에게 돌려주고,
/// 한 번에 하나만 열린다.
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct QuickPanelFocusTests {
    private let fixture: WiringFixture
    private let escapeKey = #selector(NSResponder.cancelOperation(_:))
    private let returnKey = #selector(NSResponder.insertNewline(_:))

    init() throws {
        fixture = try WiringFixture()
    }

    private func type(_ text: String, into view: NSTextView?) throws {
        try #require(view).insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - 포커스 돌려주기

    @Test func closingCaptureWithEscapeReturnsKeyToTheNoteThatHadIt() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        let other = try fixture.open("다른 노트")
        fixture.pretendKey(writing)

        fixture.router.route(.openCapture)
        // 여는 것만으로는 노트에게 아무것도 시키지 않는다.
        #expect(fixture.keyRequests(writing) == 0)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)

        #expect(!fixture.capture.isVisible)
        #expect(fixture.keyRequests(writing) == 1)
        // 맨 앞에 겹친 노트가 아니라 쓰던 노트다.
        #expect(fixture.keyRequests(other) == 0)
    }

    /// ↵로 넣은 뒤에도, 단축키로 다시 눌러 닫은 뒤에도 쓰던 노트로 돌아간다.
    @Test func submittingOrTogglingCaptureAlsoReturnsKey() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)

        fixture.router.route(.openCapture)
        try type("우유 사기", into: fixture.capture.inputView)
        fixture.capture.performSubmit()
        #expect(fixture.keyRequests(writing) == 1)

        fixture.commands.perform(.quickCapture)
        fixture.commands.perform(.quickCapture)
        #expect(!fixture.capture.isVisible)
        #expect(fixture.keyRequests(writing) == 2)
    }

    /// 열 때 키 창인 노트가 없었으면(다른 앱을 쓰다가 전역 단축키로 열었다) 닫혀도 어느 노트도 키 창으로
    /// 만들지 않는다. 키 입력은 앞에 있던 앱으로 돌아간다.
    @Test func nothingTakesKeyWhenNoNoteHadIt() throws {
        defer { fixture.cleanUp() }
        let notes = [try fixture.open("하나"), try fixture.open("둘")]
        fixture.pretendKey(nil)

        fixture.router.route(.openCapture)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        fixture.router.route(.openBrowse(anchor: nil))
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)

        #expect(notes.map(fixture.keyRequests) == [0, 0])
    }

    @Test func closingBrowseWithEscapeReturnsKeyToTheNoteThatHadIt() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        let other = try fixture.open("다른 노트")
        fixture.pretendKey(writing)

        fixture.commands.perform(.findNote)
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)

        #expect(!fixture.browse.isVisible)
        #expect(fixture.keyRequests(writing) == 1)
        #expect(fixture.keyRequests(other) == 0)
    }

    /// 노트 찾기에서 다른 노트를 고르면 그 노트만 키 창이 된다. 쓰던 노트로 돌아갔다가 넘어가지 않는다.
    @Test func choosingANoteInBrowseDoesNotBounceThroughThePreviousNote() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        let other = try fixture.open("다른 노트")
        fixture.pretendKey(writing)

        fixture.commands.perform(.findNote)
        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        #expect(fixture.keyRequests(other) == 1)
        #expect(fixture.keyRequests(writing) == 0)
    }

    /// 캡처의 ⌘↵는 새 노트가 키 창이 된다. 쓰던 노트로 돌아가지 않는다.
    @Test func captureAsNewNoteLeavesKeyWithTheNewNote() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)

        fixture.router.route(.openCapture)
        try type("분기 회고", into: fixture.capture.inputView)
        fixture.capture.performSubmitAsNewNote()

        let created = try #require(fixture.notePanels.openNoteIDs.last)
        #expect(created != writing)
        #expect(fixture.keyRequests(created) == 1)
        #expect(fixture.keyRequests(writing) == 0)
    }

    /// 화면이 닫힌 뒤에도 노트 창은 전처럼 키 창이 될 수 있다(앱이 시키면 되고, 저절로는 되지 않는다).
    @Test func notesCanStillBecomeKeyAfterThePanelsClose() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.open("노트")
        fixture.pretendKey(nil)
        fixture.router.route(.openCapture)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        fixture.router.route(.openBrowse(anchor: note))
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(note) == 0)

        fixture.notePanels.focusBody(of: note)
        #expect(fixture.keyRequests(note) == 1)
        #expect(fixture.notePanels.focusNextNote() == note)
        #expect(fixture.keyRequests(note) == 2)
    }

    // MARK: - 한 번에 하나만

    /// 노트 찾기가 열려 있을 때 캡처를 열면 노트 찾기가 닫힌다. 그 사이에 쓰던 노트를 키 창으로 만들지 않고,
    /// 캡처가 닫힐 때 처음에 쓰던 노트로 돌려준다.
    @Test func openingCaptureClosesBrowseAndCarriesTheRememberedNote() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)
        fixture.commands.perform(.findNote)
        // 노트 찾기가 키 창을 가져간 뒤다.
        fixture.pretendKey(nil)

        fixture.router.route(.openCapture)

        #expect(fixture.capture.isVisible)
        #expect(!fixture.browse.isVisible)
        #expect(fixture.keyRequests(writing) == 0)

        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(writing) == 1)
    }

    @Test func openingBrowseClosesCaptureAndCarriesTheRememberedNote() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)
        fixture.router.route(.openCapture)
        try type("적던 글", into: fixture.capture.inputView)
        fixture.pretendKey(nil)

        fixture.commands.performStatusMenu(.findNote)

        #expect(fixture.browse.isVisible)
        #expect(!fixture.capture.isVisible)
        #expect(fixture.quickPanels.isAnyVisible)
        #expect(fixture.keyRequests(writing) == 0)
        // 캡처에 적던 글은 넣지 않는다.
        #expect(try fixture.notes.list().notes.map(\.body) == [""])

        try #require(fixture.browse.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(writing) == 1)
        #expect(!fixture.quickPanels.isAnyVisible)
    }
}

extension QuickPanelFocusTests {
    @Test func requestSwitchKeepsBothDraftsAndReturnsExternalFocus() throws {
        defer { fixture.cleanUp() }
        let id = try fixture.open("쓰던 노트")
        fixture.pretendKey(id)
        fixture.isAppActive = false
        fixture.router.route(.requestAgent)
        let window = fixture.capture.window
        try type("내일 세 시 회의 요약", into: fixture.capture.inputView)
        fixture.quickPanels.toggleCapture()
        try type("메모 초안", into: fixture.capture.inputView)
        fixture.router.route(.requestAgent)
        #expect(fixture.capture.window === window && fixture.capture.inputView?.string == "내일 세 시 회의 요약")
        #expect(fixture.capture.underlinedRanges.isEmpty)
        fixture.quickPanels.toggleCapture()
        #expect(fixture.capture.inputView?.string == "메모 초안")
        fixture.router.route(.requestAgent)
        var sends: [String] = []
        fixture.capture.onRequest = { text in sends.append(text); return true }
        fixture.capture.performSubmitAsNewNote()
        #expect(sends.isEmpty && fixture.capture.isVisible)
        fixture.capture.performSubmit()
        fixture.capture.performSubmit()
        #expect(sends == ["내일 세 시 회의 요약"] && !fixture.capture.isVisible)
        #expect(fixture.keyRequests(id) == 0)
    }
}
