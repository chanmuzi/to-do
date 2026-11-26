import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct CommandReturnTests {
    @Test func windowRoutesCommandReturnExactlyOnce() throws {
        for prefix in ["+ ", "+ ## "] {
            for children in ["", "\n\t자식"] {
                for offset in [0, 1, 2] {
                    for selected in [false, true] {
                        let h = try EditorHarness(prefix + "제목" + children)
                        if children.isEmpty {
                            h.editor.load(text: h.editor.text, openedEmptyToggleLines: [0])
                        }
                        h.place(at: prefix.utf16.count + offset)
                        if selected { h.controller.selectBlocks() }
                        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                            timestamp: 0, windowNumber: h.window.windowNumber, context: nil,
                            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                        #expect(h.view.canPerformFormat(.toggleDone))
                        #expect(h.window.performKeyEquivalent(with: event))
                        #expect(h.editor.foldedLines == [0])
                        #expect(h.window.performKeyEquivalent(with: event))
                        #expect(h.editor.foldedLines.isEmpty)
                        #expect(h.foldChanges == [[0], []])
                    }
                }
            }
        }
    }

    @Test func commandReturnCommitsMarkedTitleAndFolds() throws {
        let h = try EditorHarness.at("+ 제목|\n\t자식")
        h.mark("한")
        #expect(h.view.hasMarkedText())
        #expect(h.view.canPerformFormat(.toggleDone))
        #expect(h.key(36, "\r", .command))
        #expect(!h.view.hasMarkedText())
        #expect(h.editor.text == "+ 제목한\n\t자식")
        #expect(h.editor.foldedLines == [0])
    }
}
