import AppKit
import Testing
import Theme
@testable import Editor

@MainActor
@Suite struct MarkdownEditorTextTests {
    @Test func textGoesInAndComesOutUnchanged() throws {
        let source = "# 제목\n[ ] ==형광=={3}\n\t+ 토글\n```\ncode\n```\n"
        let h = try EditorHarness(source)
        #expect(h.editor.text == source)
        #expect(h.view.string == source)
        // 넣을 때는 알리지 않는다.
        #expect(h.changes.isEmpty)
    }

    @Test func settingTheSameTextKeepsCaretAndUndoHistory() throws {
        let h = try EditorHarness("가나다")
        h.editor.selectedRange = NSRange(location: 2, length: 0)
        h.type("!")
        h.editor.text = "가나!다"
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 0))
        #expect(h.editor.undoManager.canUndo)
        // 다른 글을 넣으면 커서는 가능한 자리에 남고 되돌리기 기록은 비운다.
        h.editor.text = "가"
        #expect(h.editor.selectedRange == NSRange(location: 1, length: 0))
        #expect(!h.editor.undoManager.canUndo)
        #expect(h.changes == ["가나!다"])
    }

    @Test func storedTextCarriesNoStyling() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 4)
        let storage = try #require(h.view.textStorage)
        var keys = Set<NSAttributedString.Key>()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
            keys.formUnion(attributes.keys)
        }
        #expect(keys == [.font, .foregroundColor])
        #expect(storage.string == DemoNote.text)
    }

    @Test func typingReportsEveryChange() throws {
        let h = try EditorHarness()
        h.type("가나")
        #expect(h.changes == ["가", "가나"])
    }
}

@MainActor
@Suite struct MarkdownEditorInputTests {
    @Test func markdownTriggers() throws {
        let h = try EditorHarness()
        h.type("# 제목")
        #expect(h.document.lines[0].kind == .heading(1))
        h.press(NSResponder.newline)
        h.type("[] 할 일")
        #expect(h.editor.text == "# 제목\n[ ] 할 일")
        #expect(h.document.lines[1].kind == .todo(done: false))
        h.press(NSResponder.newline)
        h.type("둘째")
        h.press(NSResponder.newline)
        // 빈 항목에서 Return 하면 목록이 끝난다.
        h.press(NSResponder.newline)
        h.type("- 글머리표")
        h.press(NSResponder.newline)
        h.press(NSResponder.newline)
        h.type("> 토글")
        #expect(h.editor.text == "# 제목\n[ ] 할 일\n[ ] 둘째\n- 글머리표\n+ 토글")
        #expect(h.document.lines.map(\.kind) == [.heading(1), .todo(done: false), .todo(done: false), .bullet, .toggle])
    }

    @Test func tabAndShiftTabChangeTheLevel() throws {
        let h = try EditorHarness("- 하나\n- 둘")
        h.caret(atEndOfLine: 1)
        h.press(NSResponder.tab)
        // 부모(`- 하나`)보다 한 단계 깊게까지만 들어간다(D-043).
        h.press(NSResponder.tab)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "- 하나\n\t- 둘")
        #expect(h.document.lines[1].level == 1)
        #expect(h.editor.selectedRange.location == h.document.lines[1].end)
        h.press(NSResponder.backtab)
        #expect(h.editor.text == "- 하나\n- 둘")
    }

    @Test func backspaceRemovesTheMarkerThenJoinsLines() throws {
        let h = try EditorHarness("가\n[ ] 나")
        h.editor.selectedRange = NSRange(location: h.document.lines[1].contentStart, length: 0)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "가\n나")
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "가나")
    }

    @Test func codeFenceThenReturnMakesABlock() throws {
        let h = try EditorHarness()
        h.type("```")
        h.press(NSResponder.newline)
        h.type("let x = 1")
        #expect(h.editor.text == "```\nlet x = 1\n```")
        #expect(h.document.lines.map(\.kind) == [.fenceOpen, .code, .fenceClose])
    }

    @Test func leftArrowSkipsTheHiddenMarker() throws {
        let h = try EditorHarness("가\n[ ] 나")
        h.editor.selectedRange = NSRange(location: h.document.lines[1].contentStart, length: 0)
        h.view.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        #expect(h.editor.selectedRange == NSRange(location: 1, length: 0))
        h.view.doCommand(by: #selector(NSResponder.moveRight(_:)))
        #expect(h.editor.selectedRange == NSRange(location: h.document.lines[1].contentStart, length: 0))
    }

    @Test func actionsRunTheShortcutCommands() throws {
        let h = try EditorHarness("형광")
        h.editor.selectedRange = NSRange(location: 0, length: 2)
        h.perform(.highlight)
        h.perform(.highlight)
        #expect(h.editor.text == "==형광=={2}")
        h.perform(.highlight)
        h.perform(.highlight)
        h.perform(.highlight)
        #expect(h.editor.text == "형광")
        h.perform(.bold)
        #expect(h.editor.text == "**형광**")
        h.perform(.toggleTodo)
        h.perform(.toggleDone)
        #expect(h.editor.text == "[x] **형광**")
        h.perform(.heading(2))
        #expect(h.editor.text == "## **형광**")
    }

    @Test func moveLineKeepsTheFoldWithItsToggle() throws {
        let h = try EditorHarness("+ 토글\n\t- 안\n밖")
        h.editor.foldedLines = [0]
        h.caret(atEndOfLine: 0)
        h.perform(.moveLineDown)
        #expect(h.editor.text == "밖\n+ 토글\n\t- 안")
        #expect(h.editor.foldedLines == [1])
        #expect(h.foldChanges == [[1]])
    }
}

@MainActor
@Suite struct MarkdownEditorUndoTests {
    @Test func undoAndRedoStepThroughEdits() throws {
        let h = try EditorHarness("- 하나")
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.newline)
        h.type("둘")
        h.press(NSResponder.tab)
        h.perform(.toggleTodo)
        let final = "- 하나\n\t[ ] 둘"
        #expect(h.editor.text == final)

        var seen: [String] = []
        while h.editor.undoManager.canUndo {
            h.editor.undoManager.undo()
            seen.append(h.editor.text)
        }
        #expect(seen == ["- 하나\n\t- 둘", "- 하나\n- 둘", "- 하나\n- ", "- 하나"])
        while h.editor.undoManager.canRedo { h.editor.undoManager.redo() }
        #expect(h.editor.text == final)
    }

    @Test func stylingPassesDoNotTouchUndoOrText() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 1)
        h.type("!")
        // 커서를 옮기고(기호가 나타났다 사라짐), 접고, 전체를 다시 입혀도 원문과 되돌리기는 그대로다.
        h.caret(atEndOfLine: 4)
        h.caret(atEndOfLine: 7)
        h.editor.foldedLines = [5]
        h.controller.restyleAll()
        h.editor.foldedLines = []
        #expect(h.changes.count == 1)
        #expect(h.view.string == h.editor.text)
        h.editor.undoManager.undo()
        #expect(h.editor.text == DemoNote.text)
        #expect(!h.editor.undoManager.canUndo)
    }

    @Test func checkboxClickIsUndoable() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 3)
        let point = try #require(h.controller.gutterPoint(forLine: 1))
        #expect(h.controller.hit(at: point) == .checkbox(line: 1))
        h.step { #expect(h.controller.handleMouseDown(at: point)) }
        #expect(h.document.lines[1].kind == .todo(done: true))
        // 커서는 제자리에 있다.
        #expect(h.editor.selectedRange.location == h.document.lines[3].end)
        h.editor.undoManager.undo()
        #expect(h.editor.text == DemoNote.text)
    }
}

@MainActor
@Suite struct MarkdownEditorCompositionTests {
    /// 한글 조합(marked text)을 흉내 낸다: ㅎ → 하 → 한 → 확정.
    @Test func restylingDoesNotBreakMarkedText() throws {
        let h = try EditorHarness("[ ] ")
        h.caret(atEndOfLine: 0)
        func mark(_ text: String) {
            let range = h.view.hasMarkedText() ? h.view.markedRange() : h.view.selectedRange()
            h.step { h.view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: range) }
        }

        mark("ㅎ")
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 4, length: 1))
        #expect(h.editor.text == "[ ] ㅎ")

        // 조합 중에 모양을 다시 입혀도(선택 변화, 전체 다시 입히기, 접힘 변화) 조합이 풀리지 않는다.
        h.controller.refreshStyling()
        h.controller.restyleAll()
        h.editor.foldedLines = []
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 4, length: 1))

        mark("하")
        h.controller.restyleAll()
        mark("한")
        #expect(h.view.hasMarkedText())
        #expect(h.editor.text == "[ ] 한")
        #expect(h.view.markedRange() == NSRange(location: 4, length: 1))

        h.step { h.view.insertText("한", replacementRange: h.view.markedRange()) }
        #expect(!h.view.hasMarkedText())
        #expect(h.editor.text == "[ ] 한")
        #expect(h.editor.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test func displayedParagraphKeepsTheMarkedTextAttributes() throws {
        let h = try EditorHarness("가")
        h.caret(atEndOfLine: 0)
        h.step { h.view.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0), replacementRange: h.view.selectedRange()) }
        let storage = try #require(h.view.textStorage)
        let stored = storage.attributes(at: 1, effectiveRange: nil)
        let shown = try h.display(line: 0).attributes(at: 1, effectiveRange: nil)
        // 입력기가 원문에 붙인 속성(밑줄 등)은 화면 문단에도 그대로 있다.
        for key in stored.keys where key != .font && key != .foregroundColor {
            #expect(shown[key] != nil, "\(key.rawValue)")
        }
    }

    @Test func commandsAreLeftToTheInputMethodWhileComposing() throws {
        let h = try EditorHarness("- ")
        h.caret(atEndOfLine: 0)
        h.step { h.view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: h.view.selectedRange()) }
        // 조합 중에는 Tab, Return, ⌫ 를 가로채지 않는다.
        for selector in [NSResponder.tab, NSResponder.newline, NSResponder.backspace] {
            #expect(!h.controller.textView(h.view, doCommandBy: selector))
        }
        h.step { h.editor.perform(.bold) }
        h.step { h.editor.perform(.indent) }
        #expect(h.editor.text == "- ㅎ")
        #expect(h.view.hasMarkedText())
        // 조합 중의 커서 이동은 감춘 기호 쪽으로 옮기지 않는다.
        let asked = NSRange(location: 0, length: 0)
        #expect(h.controller.textView(h.view, willChangeSelectionFromCharacterRange: h.view.selectedRange(), toCharacterRange: asked) == asked)
    }

    @Test func spaceTriggerWaitsForTheCompositionToEnd() throws {
        let h = try EditorHarness("[]")
        h.caret(atEndOfLine: 0)
        h.step { h.view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: h.view.selectedRange()) }
        #expect(h.controller.textView(h.view, shouldChangeTextIn: h.view.markedRange(), replacementString: " "))
    }
}
