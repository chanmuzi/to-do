import AppKit
import Testing
import Theme
@testable import NotePanel

/// 앱을 활성화하지 않고 자기 창의 main 상태와 버튼 입력 순서만 확인한다.
@MainActor @Suite(.serialized) struct NoteMainWindowTests {
    @Test func noteTakesMainBeforeButtonActivationInsteadOfKeepingLibraryMain() throws {
        let library = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 200),
                               styleMask: [.titled], backing: .buffered, defer: false)
        let note = NotePanelWindow(contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 150))
        library.isReleasedWhenClosed = false
        defer { note.close(); library.close() }
        let button = IconButton(style: PanelStyle(theme: try Theme.bundled()), symbolName: "ellipsis", iconSize: .iconLarge, label: "더 보기")
        note.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        note.contentView?.addSubview(button)
        button.frame = NSRect(x: 50, y: 50, width: 18, height: 18)
        library.orderFrontRegardless()
        note.orderFrontRegardless()
        library.makeMain()
        #expect(library.canBecomeMain)
        var presses = 0
        var activations = 0
        button.onPress = { presses += 1 }
        note.onButtonPress = {
            activations += 1
            // 시험 실행기는 앱을 활성화하지 않으므로 실제 main 플래그는 false다.
            // 이벤트가 활성화 콜백 전에 노트를 main 후보로 지정해야 한다.
            #expect(note.canBecomeMain)
            #expect(note.mainRequestCount > 0)
        }
        RealClick.click(button)
        #expect(presses == 1)
        #expect(activations == 1)
        #expect(library.isVisible)
    }

    @Test func passiveWindowCannotBecomeMain() {
        let note = NotePanelWindow(contentRect: .zero)
        defer { note.close() }
        note.allowsKey = false
        #expect(!note.canBecomeMain)
    }
}
