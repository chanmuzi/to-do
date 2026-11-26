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
        #expect(h.editor.text == "**==글자=={노랑}**")
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.nine, characters: "(", modifiers: [.command, .shift]))) }
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: Key.returnKey, characters: "\r", modifiers: .command))) }
        #expect(h.editor.text == "[x] **==글자=={노랑}**")
    }

    @Test func koreanInputSourceDoesNotChangeTheShortcut() throws {
        // 두벌식에서 B 자리는 "ㅠ"다. 글자가 아니라 키 자리로 견주므로 그대로 굵게가 된다.
        let h = try EditorHarness("글자")
        h.editor.selectedRange = NSRange(location: 0, length: 2)
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: EditorShortcuts.Key.b, characters: "ㅠ", modifiers: .command))) }
        #expect(h.editor.text == "**글자**")
    }

    @Test func formattingTableShortcutsDispatchFromTextView() throws {
        typealias Key = EditorShortcuts.Key
        let shortcuts: [(UInt16, String, NSEvent.ModifierFlags, String)] = [
            (Key.x, "X", [.shift, .command], "~~글자~~"),
            (Key.h, "H", [.shift, .command], "==글자=={노랑}"),
            (Key.e, "e", .command, "`글자`"),
            (Key.c, "c", [.option, .command], "```\n글자\n```"),
            (Key.one, "1", [.option, .command], "# 글자"),
            (Key.two, "2", [.option, .command], "## 글자"),
            (Key.three, "3", [.option, .command], "### 글자")
        ]
        for (code, character, modifiers, expected) in shortcuts {
            let h = try EditorHarness.at("|글자|")
            let event = try keyEvent(h, code: code, characters: character, modifiers: modifiers)
            h.step { #expect(h.view.performKeyEquivalent(with: event)) }
            #expect(h.editor.text == expected)
        }
        let h = try EditorHarness.at("|글자|")
        let event = try keyEvent(h, code: Key.l, characters: "l", modifiers: .command)
        #expect(h.view.performKeyEquivalent(with: event))
        #expect(h.controller.linkSession != nil)
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

    /// 창이 키 창이 아니면 본문에 포커스가 있어도 편집 단축키를 받지 않는다. 키 창이 아닌 창의 뷰에도
    /// `performKeyEquivalent`가 올 수 있고, 그때 받으면 사용자가 보고 있지 않은 노트의 글이 바뀐다.
    @Test func shortcutsAreIgnoredWhenTheWindowIsNotKey() throws {
        let h = try EditorHarness("글자")
        h.editor.selectedRange = NSRange(location: 0, length: 2)
        // 하네스는 키 창을 만들지 않고 "편집 중인 것으로 보기"를 켜 둔다. 끄면 키 창이 아닌 창 그대로다.
        h.editor.controller.forcesActiveAppearance = false
        #expect(h.window.firstResponder === h.view)
        #expect(!h.window.isKeyWindow)

        #expect(!h.view.performKeyEquivalent(with: try keyEvent(h, code: EditorShortcuts.Key.b, characters: "b", modifiers: .command)))
        #expect(h.editor.text == "글자")

        h.editor.controller.forcesActiveAppearance = true
        h.step { #expect(h.view.performKeyEquivalent(with: try! keyEvent(h, code: EditorShortcuts.Key.b, characters: "b", modifiers: .command))) }
        #expect(h.editor.text == "**글자**")
    }
}
