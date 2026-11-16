import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Foundation
import Models
import Routing
import Store
import Testing
@testable import FloatingNotes

/// 캡처 바와 노트 찾기가 키 창에서 물러날 때(`NSWindow.didResignKeyNotification`)의 조립: 바깥을 눌러 닫히는 것,
/// 돋보기를 다시 눌러 닫는 것, 실패 알림 창이 키 창을 가져가도 닫히지 않는 것, ⌘W, 돌려줄 노트가 없어진 경우.
/// 시험은 실제 키 창을 만들지 않으므로 AppKit이 보내는 알림을 직접 보낸다(`WiringFixture.resignKey(_:)`).
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct QuickPanelDismissalTests {
    private let fixture: WiringFixture
    private let escapeKey = #selector(NSResponder.cancelOperation(_:))
    private let returnKey = #selector(NSResponder.insertNewline(_:))

    init() throws {
        fixture = try WiringFixture()
    }

    private func type(_ text: String, into view: NSTextView?) throws {
        try #require(view).insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - 바깥을 눌러 닫기

    /// 바깥을 누르면 닫히고, 포커스는 누른 곳에 둔다: 쓰던 노트에게 키 창을 돌려주지 않는다.
    @Test func clickingOutsideDismissesWithoutReturningKey() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)

        fixture.router.route(.openCapture)
        try type("적던 글", into: fixture.capture.inputView)
        fixture.pretendKey(nil)
        fixture.resignKey(fixture.capture.window)
        #expect(!fixture.capture.isVisible)
        #expect(fixture.keyRequests(writing) == 0)
        // 적던 글은 넣지 않는다.
        #expect(try fixture.notes.list().notes.map(\.body) == [""])

        fixture.pretendKey(writing)
        fixture.commands.perform(.findNote)
        fixture.pretendKey(nil)
        fixture.resignKey(fixture.browse.window)
        #expect(!fixture.browse.isVisible)
        #expect(!fixture.quickPanels.isAnyVisible)
        #expect(fixture.keyRequests(writing) == 0)

        // 그 뒤에 다시 열고 esc로 닫아도, 앞서 적어 둔 노트에게 뒤늦게 돌려주지 않는다.
        fixture.router.route(.openCapture)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(writing) == 0)
    }

    /// 다른 화면의 알림에는 반응하지 않는다(노트 찾기가 물러났다고 캡처 바가 닫히지 않는다).
    @Test func resignationOfAnotherWindowDoesNotDismiss() throws {
        defer { fixture.cleanUp() }
        fixture.router.route(.openBrowse(anchor: nil))
        fixture.browse.hide()
        fixture.router.route(.openCapture)
        fixture.resignKey(fixture.browse.window)
        #expect(fixture.capture.isVisible)
    }

    // MARK: - 돋보기를 다시 누르기

    /// 검토에서 나온 문제: 노트 찾기가 떠 있을 때 그 노트의 돋보기를 누르면, 누르는 순간 노트 찾기가 키 창에서
    /// 물러나 닫히고 떼는 순간의 "노트 찾기 열기"가 그것을 다시 띄웠다. 떠 있을 때 다시 고르면 닫혀야 한다(D-032).
    @Test func magnifierWhileBrowseIsOpenClosesIt() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.open("쓰던 노트")
        _ = try fixture.open("다른 노트")
        fixture.pretendKey(note)
        fixture.router.route(.openBrowse(anchor: note))
        #expect(fixture.browse.isVisible)

        // 돋보기를 누른다: 노트 창이 키 창이 되며 노트 찾기가 물러나고, 떼면 돋보기가 요청을 보낸다.
        fixture.beginPress()
        fixture.resignKey(fixture.browse.window)
        #expect(!fixture.browse.isVisible)
        fixture.releasePress()
        fixture.router.route(.openBrowse(anchor: note))
        fixture.endPress()

        #expect(!fixture.browse.isVisible)
        #expect(fixture.router.unhandled.isEmpty)

        // 닫힌 뒤에 다시 누르면 열린다.
        fixture.beginPress()
        fixture.releasePress()
        fixture.router.route(.openBrowse(anchor: note))
        fixture.endPress()
        #expect(fixture.browse.isVisible)
    }

    /// 삼키는 것은 그 누름이 닫은 노트 찾기를 같은 자리에 다시 열려는 요청뿐이다. 다른 곳을 눌러 닫은 뒤의
    /// ⌘P나 메뉴, 다른 노트의 돋보기는 그대로 연다.
    @Test func onlyTheReopenFromTheSamePressIsSwallowed() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.open("쓰던 노트")
        let other = try fixture.open("다른 노트")
        fixture.pretendKey(note)

        // 노트 본문을 눌러 닫았다(요청이 오지 않고 누름이 끝난다). 그 뒤의 ⌘P는 연다.
        fixture.router.route(.openBrowse(anchor: note))
        fixture.beginPress()
        fixture.resignKey(fixture.browse.window)
        fixture.releasePress()
        fixture.endPress()
        fixture.commands.perform(.findNote)
        #expect(fixture.browse.isVisible)

        // 뗀 일이 끝났다는 알림을 놓쳤어도(메뉴가 이벤트를 가져감) 단축키가 보낸 요청은 삼키지 않는다.
        fixture.beginPress()
        fixture.resignKey(fixture.browse.window)
        #expect(!fixture.browse.isVisible)
        fixture.currentEventType = .keyDown
        fixture.commands.perform(.findNote)
        #expect(fixture.browse.isVisible)
        fixture.endPress()

        // 다른 노트의 돋보기를 눌렀다: 닫히고 그 노트에 붙어 다시 열린다.
        fixture.beginPress()
        fixture.resignKey(fixture.browse.window)
        fixture.releasePress()
        fixture.router.route(.openBrowse(anchor: other))
        fixture.endPress()
        #expect(fixture.browse.isVisible)
        #expect(fixture.browseTitles == ["쓰던 노트(핀)"])

        // 누름 없이 키 창에서 물러난 것(다른 앱으로 넘어감)은 적어 두지 않는다. 다음 요청이 연다.
        fixture.resignKey(fixture.browse.window)
        #expect(!fixture.browse.isVisible)
        fixture.router.route(.openBrowse(anchor: other))
        #expect(fixture.browse.isVisible)

        // esc로 닫은 것도 삼키지 않는다.
        fixture.beginPress()
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)
        fixture.releasePress()
        fixture.router.route(.openBrowse(anchor: other))
        fixture.endPress()
        #expect(fixture.browse.isVisible)
    }

    // MARK: - 실패 알림 창이 키 창을 가져갈 때

    /// 검토에서 나온 문제: 노트 찾기를 열 때 목록을 읽지 못해 알림 창이 뜨면, 알림 창이 키 창을 가져가는 바람에
    /// 노트 찾기가 스스로 닫혔다. 알리는 동안에는 닫히지 않고 남은 줄이 보이며, 쓰던 노트를 건드리지 않는다.
    @Test func failureAlertTakingKeyDoesNotCloseBrowse() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.root.path)
        var resignedWhileShown = 0
        fixture.whileFailureIsShown = { [fixture] in
            resignedWhileShown += 1
            fixture.resignKey(fixture.browse.window)
        }

        fixture.router.route(.openBrowse(anchor: nil))

        #expect(fixture.shownFailures == [QuickPanels.browseFailureTitle])
        #expect(resignedWhileShown == 1)
        #expect(fixture.browse.isVisible)
        #expect(fixture.keyRequests(writing) == 0)
        // 글자를 치면 "새 노트 만들기"가 보인다.
        try type("새 계획", into: fixture.browse.inputView)
        #expect(fixture.browse.rowDescriptions == ["*create “새 계획” 새 노트 만들기"])

        // esc로 닫으면 쓰던 노트로 돌아간다.
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(writing) == 1)
    }

    /// 캡처 바도 같다: 넣지 못한 것을 알리는 동안 키 창에서 물러나도 닫히지 않고 적은 글이 남는다.
    @Test func failureAlertTakingKeyDoesNotCloseCapture() throws {
        defer { fixture.cleanUp() }
        fixture.router.route(.openCapture)
        try type("우유 사기", into: fixture.capture.inputView)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)
        fixture.whileFailureIsShown = { [fixture] in fixture.resignKey(fixture.capture.window) }

        fixture.capture.performSubmit()
        fixture.capture.performSubmitAsNewNote()

        #expect(fixture.shownFailures == [QuickPanels.captureFailureTitle, "새 노트를 만들지 못했습니다"])
        #expect(fixture.capture.isVisible)
        #expect(fixture.capture.inputView?.string == "우유 사기")
    }

    // MARK: - 이루어지지 못한 요청 뒤의 포커스

    /// 검토에서 나온 문제: 노트 찾기에서 고른 노트의 파일이 없어져 열지 못하면 알림만 뜨고 키 입력이 갈 곳이
    /// 없었다. 알림 뒤에 쓰던 노트가 다시 키 창이 된다.
    @Test func failedOpenFromBrowseReturnsKeyToTheNoteThatHadIt() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        let vanished = try fixture.notes.create(NoteDraft(title: "없어질 노트")).id
        fixture.pretendKey(writing)
        fixture.commands.perform(.findNote)
        #expect(fixture.browseTitles == ["없어질 노트"])
        fixture.pretendKey(nil)
        // 목록을 읽은 뒤에 다른 프로그램이 파일을 지웠다.
        try FileManager.default.removeItem(
            at: fixture.location.notesDirectory.appendingPathComponent("\(vanished.rawValue).md")
        )
        try fixture.notes.refresh()
        fixture.whileFailureIsShown = { [fixture] in fixture.resignKey(fixture.browse.window) }

        try #require(fixture.browse.inputView).doCommand(by: returnKey)

        #expect(fixture.shownFailures == ["노트를 열지 못했습니다"])
        #expect(!fixture.browse.isVisible)
        #expect(fixture.keyRequests(writing) == 1)
        #expect(!fixture.notePanels.openNoteIDs.contains(vanished))
    }

    // MARK: - 돌려줄 노트가 없어졌을 때

    /// 검토에서 나온 문제: 화면이 떠 있는 동안 적어 둔 노트가 닫히면 닫힌 뒤에 어느 노트도 키 창이 되지 않았다.
    /// 앱이 앞에 있으면 맨 앞 노트가 이어받고, 앞에 있지 않으면(다른 앱을 쓰는 중) 아무것도 하지 않는다.
    @Test func closedRememberedNoteFallsBackToTheFrontmostNoteWhenTheAppIsActive() throws {
        defer { fixture.cleanUp() }
        let other = try fixture.open("남는 노트")
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)

        fixture.isAppActive = true
        fixture.router.route(.openCapture)
        // 캡처 바가 키 창을 가져간 뒤에 쓰던 노트가 닫혔다.
        fixture.pretendKey(nil)
        fixture.notePanels.closeWindow(writing)
        #expect(fixture.keyRequests(other) == 0)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(other) == 1)

        // 숨긴 중이면 돌려줄 창도, 이어받을 창도 없다.
        fixture.pretendKey(other)
        fixture.router.route(.openBrowse(anchor: nil))
        fixture.pretendKey(nil)
        fixture.notePanels.toggleAllHidden()
        try #require(fixture.browse.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(other) == 1)
        fixture.notePanels.toggleAllHidden()

        // 앱이 앞에 있지 않으면 이어받지 않는다(쓰던 앱이 입력을 받는다).
        let third = try fixture.open("셋째 노트")
        fixture.pretendKey(third)
        fixture.isAppActive = false
        fixture.router.route(.openCapture)
        fixture.pretendKey(nil)
        fixture.notePanels.closeWindow(third)
        try #require(fixture.capture.inputView).doCommand(by: escapeKey)
        #expect(fixture.keyRequests(other) == 1)
    }

    // MARK: - ⌘W

    /// ⌘W("창 닫기")는 떠 있는 캡처 바나 노트 찾기를 닫는다(esc와 같다). 노트 창은 닫지 않는다.
    @Test func closeWindowCommandClosesTheVisiblePanelNotTheNote() throws {
        defer { fixture.cleanUp() }
        let writing = try fixture.open("쓰던 노트")
        fixture.pretendKey(writing)

        fixture.router.route(.openCapture)
        fixture.commands.perform(.closeWindow)
        #expect(!fixture.capture.isVisible)
        #expect(fixture.notePanels.openNoteIDs == [writing])
        #expect(fixture.keyRequests(writing) == 1)

        fixture.commands.perform(.findNote)
        fixture.commands.perform(.closeWindow)
        #expect(!fixture.browse.isVisible)
        #expect(fixture.notePanels.openNoteIDs == [writing])
        #expect(fixture.keyRequests(writing) == 2)

        // 떠 있는 화면이 없으면 전처럼 키 창인 노트의 창을 닫는다.
        fixture.commands.perform(.closeWindow)
        #expect(fixture.notePanels.openNoteIDs.isEmpty)
    }

    // MARK: - 이어지지 않은 화면

    /// 앱에서는 라이브러리가 아직 이어져 있지 않다. 노트 찾기에 "라이브러리 열기" 줄이 없다.
    @Test func browseHasNoLibraryRowUntilTheLibraryIsConnected() throws {
        defer { fixture.cleanUp() }
        _ = try fixture.notes.create(NoteDraft(title: "노트"))
        #expect(!fixture.router.isConnected(.openLibrary))
        #expect(fixture.router.route(.openLibrary) == .unconnected)

        fixture.router.route(.openBrowse(anchor: nil))
        #expect(fixture.browse.rowDescriptions.count == 2)
        #expect(!fixture.browse.rowDescriptions.contains { $0.contains("library") })
        try type("없는 말", into: fixture.browse.inputView)
        #expect(fixture.browse.rowDescriptions == ["*create “없는 말” 새 노트 만들기"])
    }
}
