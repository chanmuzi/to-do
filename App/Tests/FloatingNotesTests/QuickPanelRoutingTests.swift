import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Foundation
import Models
import Routing
import Store
import Testing
@testable import FloatingNotes

/// 빠른 캡처와 노트 찾기로 가는 길(spec 4.2): 요청, 단축키가 하는 동작, 메뉴 막대와 Dock과 앱 메뉴의 항목이
/// 모두 실제 화면에 닿는지. 그리고 하지 못한 일을 사용자에게 알리는지.
@Suite struct QuickPanelRoutingTests {
    private let fixture: WiringFixture

    init() throws {
        fixture = try WiringFixture()
    }

    // MARK: - 빠른 캡처

    @Test func captureRouteTogglesTheBar() {
        defer { fixture.cleanUp() }
        #expect(Route.openCapture.isConnected)
        #expect(!fixture.capture.isVisible)

        fixture.router.route(.openCapture)
        #expect(fixture.capture.isVisible)
        fixture.router.route(.openCapture)
        #expect(!fixture.capture.isVisible)

        #expect(fixture.router.unhandled.isEmpty)
    }

    /// ⌃⌥N(전역 단축키가 부르는 동작), 메뉴 막대와 Dock 메뉴의 "빠른 캡처"가 같은 바를 연다.
    @Test func hotKeyCommandAndMenusReachTheCaptureBar() {
        defer { fixture.cleanUp() }
        fixture.commands.perform(.quickCapture)
        #expect(fixture.capture.isVisible)
        fixture.commands.performStatusMenu(.quickCapture)
        #expect(!fixture.capture.isVisible)

        // 앱 메뉴의 항목은 동작 이름으로 온다.
        let item = NSMenuItem(title: "빠른 캡처", action: nil, keyEquivalent: "")
        item.representedObject = AppCommand.quickCapture.rawValue
        fixture.commands.performMenuCommand(item)
        #expect(fixture.capture.isVisible)
    }

    // MARK: - 노트 찾기

    /// ⌘P는 키 창인 노트의 상단 줄 아래에 붙고 그 노트를 목록에서 뺀다.
    @Test func findNoteCommandAnchorsUnderTheKeyNoteAndExcludesIt() throws {
        defer { fixture.cleanUp() }
        #expect(Route.openBrowse(anchor: nil).isConnected)
        let current = try fixture.open("쓰던 노트")
        _ = try fixture.open("다른 노트")
        fixture.pretendKey(current)

        fixture.commands.perform(.findNote)

        #expect(fixture.browse.isVisible)
        #expect(fixture.browseTitles == ["다른 노트(핀)"])
        // 그 노트의 창 아래, 창의 가로 범위 안에 놓인다.
        let noteFrame = try #require(fixture.notePanels.window(for: current)).frame
        let frame = fixture.browse.settledFrame
        #expect(frame.maxY < noteFrame.maxY)
        #expect(frame.maxX <= noteFrame.maxX && frame.maxX > noteFrame.minX)
        #expect(fixture.router.unhandled.isEmpty)

        // 떠 있을 때 다시 누르면 닫힌다.
        fixture.commands.perform(.findNote)
        #expect(!fixture.browse.isVisible)
    }

    /// 노트의 돋보기는 그 노트를 붙일 곳으로 보낸다(키 창이 아니어도).
    @Test func magnifierRouteAnchorsUnderThatNote() throws {
        defer { fixture.cleanUp() }
        let first = try fixture.open("하나")
        let second = try fixture.open("둘")
        fixture.pretendKey(first)

        fixture.router.route(.openBrowse(anchor: second))

        #expect(fixture.browseTitles == ["하나(핀)"])
        let noteFrame = try #require(fixture.notePanels.window(for: second)).frame
        #expect(fixture.browse.settledFrame.maxY < noteFrame.maxY)
    }

    /// 메뉴 막대, Dock, 앱 메뉴의 "노트 찾기"와, 키 창인 노트가 없을 때의 ⌘P는 노트에 붙지 않고 모든 노트를 보인다.
    @Test func menusOpenBrowseUnanchoredWithEveryNote() throws {
        defer { fixture.cleanUp() }
        let first = try fixture.open("하나")
        _ = try fixture.open("둘")
        fixture.pretendKey(first)
        fixture.router.route(.openBrowse(anchor: first))
        let anchored = fixture.browse.settledFrame
        fixture.browse.hide()

        fixture.commands.performStatusMenu(.findNote)
        #expect(fixture.browse.isVisible)
        #expect(Set(fixture.browseTitles) == ["하나(핀)", "둘(핀)"])
        #expect(fixture.browse.settledFrame.origin != anchored.origin)
        fixture.browse.hide()

        fixture.pretendKey(nil)
        fixture.commands.perform(.findNote)
        #expect(Set(fixture.browseTitles) == ["하나(핀)", "둘(핀)"])
    }

    /// 붙일 노트의 창이 보이지 않으면(닫힘, 모두 숨김) 붙이지 않고 그 노트도 목록에 둔다.
    @Test func anchorWithoutAVisibleWindowFallsBackToTheScreen() throws {
        defer { fixture.cleanUp() }
        let closed = try fixture.notes.create(NoteDraft(title: "닫힌 노트")).id
        let shown = try fixture.open("떠 있는 노트")

        fixture.router.route(.openBrowse(anchor: closed))
        #expect(Set(fixture.browseTitles) == ["닫힌 노트", "떠 있는 노트(핀)"])
        fixture.browse.hide()

        fixture.notePanels.toggleAllHidden()
        fixture.router.route(.openBrowse(anchor: shown))
        #expect(Set(fixture.browseTitles) == ["닫힌 노트", "떠 있는 노트(핀)"])
        // 노트 찾기를 여는 것만으로는 숨김이 풀리지 않는다.
        #expect(fixture.notePanels.areNotesHidden)
    }

    // MARK: - 조립되지 않았을 때와 실패

    /// 화면을 잇지 않은 라우터는 요청을 삼키지 않고 기록한다.
    @Test func routerWithoutPanelsRecordsTheRequests() {
        defer { fixture.cleanUp() }
        fixture.router.quickPanels = nil
        fixture.router.route(.openCapture)
        fixture.router.route(.openBrowse(anchor: nil))
        #expect(fixture.router.unhandled == [.openCapture, .openBrowse(anchor: nil)])
    }

    /// 캡처한 글을 넣지 못하면 기록만 하지 않고 다른 요청의 실패와 같은 알림으로 보여 준다.
    @Test func failedCaptureIsShownToTheUser() throws {
        defer { fixture.cleanUp() }
        fixture.router.route(.openCapture)
        let input = try #require(fixture.capture.inputView)
        input.insertText("우유 사기", replacementRange: NSRange(location: NSNotFound, length: 0))
        // 노트 폴더에 쓸 수 없게 한다(오늘 노트를 만들지 못한다).
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)

        fixture.capture.performSubmit()

        #expect(fixture.shownFailures == [QuickPanels.captureFailureTitle])
        // 적은 글은 그대로이고 바도 열려 있다.
        #expect(fixture.capture.isVisible)
        #expect(input.string == "우유 사기")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
        fixture.capture.performSubmit()
        #expect(fixture.shownFailures.count == 1)
        #expect(!fixture.capture.isVisible)
        #expect(try fixture.notes.list().notes.map(\.body) == ["[ ] 우유 사기\n"])
    }

    /// 노트 찾기를 열 때 목록을 읽지 못하면 알린다.
    @Test func failedBrowseOpenIsShownToTheUser() throws {
        defer { fixture.cleanUp() }
        _ = try fixture.notes.create(NoteDraft(title: "읽지 못할 노트"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.root.path)

        fixture.router.route(.openBrowse(anchor: nil))

        #expect(fixture.shownFailures == [QuickPanels.browseFailureTitle])
        #expect(fixture.logLines.contains { $0.contains("노트 목록을 읽지 못했습니다") })
    }

    /// 캡처의 ⌘↵와 노트 찾기의 "새 노트 만들기"가 보낸 새 노트 요청이 실패해도 알림이 뜬다.
    @Test func failedNewNoteFromThePanelsIsShownToTheUser() throws {
        defer { fixture.cleanUp() }
        fixture.router.route(.openCapture)
        let input = try #require(fixture.capture.inputView)
        input.insertText("새 노트", replacementRange: NSRange(location: NSNotFound, length: 0))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)

        fixture.capture.performSubmitAsNewNote()

        #expect(fixture.shownFailures == ["새 노트를 만들지 못했습니다"])
        #expect(fixture.notePanels.openNoteIDs.isEmpty)
    }
}
