import AppKit
import Testing
@testable import Editor

/// 키 이벤트를 만들어 텍스트 뷰의 실제 처리 경로(`performKeyEquivalent`, `keyDown`)에 넣는다.
@MainActor
@Suite struct MarkdownEditorKeyEventTests {
    private func keyEvent(_ h: EditorHarness, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: h.window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        ))
    }

    @Test func commandShortcutsReachTheEditor() throws {
        let h = try EditorHarness("글자")
        h.editor.selectedRange = NSRange(location: 0, length: 2)
        typealias Key = EditorShortcuts.Key
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.b, characters: "b", modifiers: .command))) }
        #expect(h.editor.text == "**글자**")
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.h, characters: "H", modifiers: [.command, .shift]))) }
        #expect(h.editor.text == "**==글자==**")
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.nine, characters: "(", modifiers: [.command, .shift]))) }
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.returnKey, characters: "\r", modifiers: .command))) }
        #expect(h.editor.text == "[x] **==글자==**")
    }

    @Test func koreanInputSourceDoesNotChangeTheShortcut() throws {
        // 두벌식에서 B 자리는 "ㅠ"다. 글자가 아니라 키 자리로 견주므로 그대로 굵게가 된다.
        let h = try EditorHarness("글자")
        h.editor.selectedRange = NSRange(location: 0, length: 2)
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: EditorShortcuts.Key.b, characters: "ㅠ", modifiers: .command))) }
        #expect(h.editor.text == "**글자**")
    }

    @Test func otherShortcutsPassThrough() throws {
        let h = try EditorHarness("글자")
        // ⌘W(창 닫기) 같은 노트 창의 단축키는 편집기가 먹지 않는다.
        #expect(!h.view.performKeyEquivalent(with: try keyEvent(h, code: 13, characters: "w", modifiers: .command)))
        #expect(h.editor.text == "글자")
    }

    @Test func shortcutsAreIgnoredWithoutFocus() throws {
        let h = try EditorHarness("글자")
        h.window.makeFirstResponder(nil)
        #expect(!h.view.performKeyEquivalent(with: try keyEvent(h, code: EditorShortcuts.Key.b, characters: "b", modifiers: .command)))
        #expect(h.editor.text == "글자")
    }
}
