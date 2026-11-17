import AppKit
import Testing
@testable import Editor

@MainActor
@Suite struct InputClientTriggerTests {
    @Test(arguments: ["[]", "[ ]", "\"", "|", "-", ">", "#"])
    func unspecifiedReplacementRange(marker: String) throws {
        let h = try EditorHarness("")
        for c in marker + " " {
            h.step { h.view.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        let expected = ["[]": "[ ] ", "[ ]": "[ ] ", "\"": "> ", "|": "> ", "-": "- ", ">": "+ ", "#": "# "]
        #expect(h.editor.text == expected[marker])
        #expect(!h.view.isAutomaticQuoteSubstitutionEnabled)
    }

    @Test(arguments: ["[]", "[ ]", "\""])
    func interpretedKeyEvents(marker: String) throws {
        let h = try EditorHarness("")
        for c in marker + " " {
            let code: UInt16 = c == " " ? 49 : c == "[" ? 33 : c == "]" ? 30 : 39
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: c == "\"" ? .shift : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: h.window.windowNumber, context: nil, characters: String(c),
                charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: code))
            h.step { h.view.keyDown(with: event) }
        }
        #expect(h.editor.text == (marker == "\"" ? "> " : "[ ] "))
        #expect(!h.view.isAutomaticQuoteSubstitutionEnabled)
    }
    @Test(arguments: ["[]", "[ ]", "\""])
    func committedCompositionThenSpace(marker: String) throws {
        let h = try EditorHarness("")
        h.mark("ㅎ")
        h.commit("한")
        h.press(NSResponder.newline)
        for c in marker + " " {
            h.step { h.view.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        #expect(h.editor.text == "한\n" + (marker == "\"" ? "> " : "[ ] "))
    }

    @Test(arguments: ["[]", "[ ]", "\""])
    func inputClientCommitsMarkedTriggerWithSpace(marker: String) throws {
        let h = try EditorHarness("")
        h.mark(marker)
        h.step { h.view.insertText(marker + " ", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        #expect(h.editor.text == (marker == "\"" ? "> " : "[ ] "))
        #expect(!h.view.hasMarkedText())
    }

    @Test(arguments: ["[]", "[ ]", "\""])
    func attributedCommitAtExplicitMarkedRangeKeepsUndo(marker: String) throws {
        let h = try EditorHarness.at("- 부모\n\t- |할 일")
        h.mark(marker)
        let range = h.view.markedRange()
        h.step {
            h.view.insertText(NSAttributedString(string: marker + " "), replacementRange: range)
        }
        let expected = "- 부모\n\t" + (marker == "\"" ? "> " : "- [ ] ") + "할 일"
        #expect(h.editor.text == expected)
        h.undo()
        // 조합과 확정/변환은 한 단계로 되돌아가 원래 하위 목록 줄을 복원한다.
        #expect(h.editor.text == "- 부모\n\t- 할 일")
        h.redo()
        #expect(h.editor.text == expected)
        #expect(h.replayMismatches.isEmpty)
    }

    @Test func midLineCommitAndUncommittedMarkersStayLiteral() throws {
        let h = try EditorHarness.at("본문 |")
        h.mark("[]")
        h.step { h.view.insertText("[] ", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        #expect(h.editor.text == "본문 [] ")
        let composing = try EditorHarness()
        composing.mark("\" ")
        #expect(composing.view.hasMarkedText())
        #expect(composing.editor.text == "\" ")
    }

}
