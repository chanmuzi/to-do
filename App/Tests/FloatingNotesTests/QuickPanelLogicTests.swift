import AppKit
import Models
import Testing
@testable import FloatingNotes

/// 캡처 바와 노트 찾기를 잇는 값 계산: 닫힐 때 키 입력을 돌려줄 곳, 노트 찾기를 붙일 창.
@Suite struct QuickPanelLogicTests {
    private let note = NoteID(rawValue: "a")

    // MARK: - 키 입력을 돌려줄 곳

    @Test func focusGoesBackToTheNoteThatWasKeyWhenThePanelOpened() {
        var focus = KeyFocusReturn()
        focus.begin(keyNote: note)
        #expect(focus.end(returnsFocus: true) == note)
        // 한 번 돌려주면 비운다.
        #expect(focus.end(returnsFocus: true) == nil)
    }

    /// 열 때 키 창인 노트가 없었으면(다른 앱을 쓰던 중, 노트를 숨긴 중) 어느 노트도 키 창으로 만들지 않는다.
    @Test func nothingIsReturnedWhenNoNoteWasKey() {
        var focus = KeyFocusReturn()
        focus.begin(keyNote: nil)
        #expect(focus.end(returnsFocus: true) == nil)
    }

    /// 바깥을 눌렀거나 다른 노트를 열었으면 포커스가 갈 곳이 따로 있다. 적어 둔 노트는 버린다.
    @Test func focusIsNotReturnedWhenItWentSomewhereElse() {
        var focus = KeyFocusReturn()
        focus.begin(keyNote: note)
        #expect(focus.end(returnsFocus: false) == nil)
        #expect(focus.end(returnsFocus: true) == nil)
        // 다시 열면 그때의 키 창을 새로 적는다.
        focus.begin(keyNote: NoteID(rawValue: "b"))
        #expect(focus.rememberedNote == NoteID(rawValue: "b"))
    }

    // MARK: - 노트 찾기를 붙일 창

    private func makeWindow(visible: Bool) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // 화면에 올리되 보이지 않게 둔다(시험이 쓰는 사람의 화면을 가리지 않게).
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        if visible { window.orderFrontRegardless() }
        return window
    }

    @Test func browseAnchorsToTheVisibleWindowOfTheGivenNoteAndExcludesIt() {
        let window = makeWindow(visible: true)
        defer { window.close() }
        var asked: [NoteID] = []

        let placement = BrowseAnchor.resolve(note) { id in
            asked.append(id)
            return window
        }

        #expect(placement.window === window)
        #expect(placement.excluded == note)
        #expect(asked == [note])
    }

    /// 붙일 노트가 없거나, 그 창이 없거나 보이지 않으면 화면 가운데 위쪽에 띄우고 아무 노트도 빼지 않는다.
    @Test func browseIsUnanchoredWithoutAVisibleNoteWindow() {
        let hidden = makeWindow(visible: false)
        defer { hidden.close() }

        let noAnchor = BrowseAnchor.resolve(nil) { _ in hidden }
        let noWindow = BrowseAnchor.resolve(note) { _ in nil }
        let hiddenWindow = BrowseAnchor.resolve(note) { _ in hidden }

        for placement in [noAnchor, noWindow, hiddenWindow] {
            #expect(placement.window == nil)
            #expect(placement.excluded == nil)
        }
    }
}
