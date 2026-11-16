import AppKit
import Testing
@testable import Editor

/// 접혀서 보이지 않는 줄은 선택과 편집이 건드리지 못한다.
@MainActor
@Suite struct FoldProtectionTests {
    /// 0 `> T`(0..<3), 1 `\tchild one`(4..<14), 2 `\tchild two`(15..<25), 3 `after`(26..<31)
    private static let source = "> T\n\tchild one\n\tchild two\nafter"
    private static let titleEnd = 3
    private static let afterStart = 26

    private func folded() throws -> EditorHarness {
        let h = try EditorHarness()
        h.editor.load(text: Self.source, foldedLines: [0])
        return h
    }

    // MARK: 선택

    @Test func shiftRightFromTheTitleJumpsOverTheFoldedLines() throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(NSResponder.shiftRight)
        // 접힌 덩어리는 통째로 들어간다. 끝이 감춘 줄 안에 놓이지 않는다.
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 23))
        h.press(NSResponder.shiftRight, times: 2)
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 25))
        // 되돌아오면 통째로 빠진다.
        h.press(NSResponder.shiftLeft, times: 3)
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 0))
        #expect(h.editor.foldedLines == [0])
    }

    @Test func shiftLeftFromTheNextLineJumpsOverTheFoldedLines() throws {
        let h = try folded()
        h.caret(at: Self.afterStart)
        h.press(NSResponder.shiftLeft)
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 23))
        h.press(NSResponder.shiftLeft)
        #expect(h.editor.selectedRange == NSRange(location: 2, length: 24))
        #expect(h.editor.foldedLines == [0])
    }

    @Test func shiftDownAndUpNeverEndInsideTheFold() throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(NSResponder.shiftDown)
        let down = h.editor.selectedRange
        #expect(down.location == 3)
        #expect(NSMaxRange(down) >= Self.afterStart)
        h.caret(at: h.document.length)
        h.press(NSResponder.shiftUp)
        let up = h.editor.selectedRange
        #expect(up.location <= Self.titleEnd)
        #expect(NSMaxRange(up) == h.document.length)
        #expect(h.editor.foldedLines == [0])
    }

    // MARK: 편집

    @Test func backspaceOverASelectionAcrossTheFoldUnfoldsInsteadOfDeleting() throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(NSResponder.shiftRight, times: 6)
        h.press(NSResponder.backspace)
        // 감춘 줄이 지워지지 않고, 무엇이 선택돼 있는지 보이도록 토글이 펴진다.
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
        #expect(h.foldChanges == [[]])
        #expect(h.changes.isEmpty)
        // 펴진 뒤에 다시 누르면 보이는 글자를 지우는 것이므로 지워진다.
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "> T")
    }

    @Test func typingOverASelectionAcrossTheFoldUnfoldsInsteadOfReplacing() throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(NSResponder.shiftRight, times: 3)
        h.type("Z")
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
    }

    @Test func backspaceOverASelectionReachingBackAcrossTheFold() throws {
        let h = try folded()
        h.caret(at: Self.afterStart)
        h.press(NSResponder.shiftLeft, times: 3)
        // 토글 줄 전체와 감춘 줄이 선택에 들어 있다.
        #expect(h.editor.selectedRange == NSRange(location: 0, length: 26))
        h.press(NSResponder.backspace)
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
    }

    @Test(arguments: [
        "deleteWordBackward:", "deleteToBeginningOfLine:", "deleteToBeginningOfParagraph:",
        "deleteBackwardByDecomposingPreviousCharacter:",
    ])
    func backwardDeletesFromTheLineAfterTheFoldKeepTheHiddenText(selector: String) throws {
        let h = try folded()
        h.caret(at: Self.afterStart)
        h.press(Selector(selector))
        // 감춘 줄의 글자는 한 글자도 사라지지 않는다.
        #expect(h.editor.text.contains("\tchild one\n\tchild two"))
        #expect(h.editor.text.hasPrefix("> T\n"))
        #expect(h.editor.text.hasSuffix("after"))
    }

    @Test func plainBackspaceAfterTheFoldUnfoldsThenJoinsVisibleLines() throws {
        let h = try folded()
        h.caret(at: Self.afterStart)
        h.press(NSResponder.backspace)
        #expect(h.editor.foldedLines == [])
        #expect(h.editor.text == "> T\n\tchild one\n\tchild twoafter")
    }

    @Test(arguments: [
        "deleteWordForward:", "deleteToEndOfLine:", "deleteToEndOfParagraph:",
    ])
    func forwardDeletesFromTheTitleEndKeepTheHiddenText(selector: String) throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(Selector(selector))
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
    }

    @Test func forwardDeleteAtTheTitleEndUnfoldsThenJoinsVisibleLines() throws {
        let h = try folded()
        h.caret(at: Self.titleEnd)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.foldedLines == [])
        // 펴진 첫 하위 줄이 제목에 이어 붙는다. 글자는 사라지지 않는다.
        #expect(h.editor.text == "> Tchild one\n\tchild two\nafter")
    }

    @Test func wordDeletesInsideVisibleTextStillWork() throws {
        let h = try folded()
        h.caret(at: h.document.length)
        h.press(#selector(NSResponder.deleteWordBackward(_:)))
        #expect(h.editor.text == "> T\n\tchild one\n\tchild two\n")
        #expect(h.editor.foldedLines == [0])
    }

    @Test func cutAndPasteAcrossTheFoldAreBlockedToo() throws {
        let h = try folded()
        let board = NSPasteboard(name: NSPasteboard.Name("floating-notes-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("X", forType: .string)
        h.editor.selectedRange = NSRange(location: 0, length: h.document.length)
        h.step { h.controller.paste(from: board) }
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
        // 펴진 뒤에는 보이는 글자를 바꾸는 것이다.
        h.step { h.controller.paste(from: board) }
        #expect(h.editor.text == "X")
    }

    @Test func commandsOverASelectionAcrossTheFoldAreBlocked() throws {
        let h = try folded()
        h.editor.selectedRange = NSRange(location: 0, length: h.document.length)
        h.perform(.toggleTodo)
        #expect(h.editor.text == Self.source)
        #expect(h.editor.foldedLines == [])
    }

    @Test func compositionOverASelectionAcrossTheFoldIsBlocked() throws {
        let h = try folded()
        h.editor.selectedRange = NSRange(location: Self.titleEnd, length: 24)
        h.mark("ㅎ")
        #expect(h.editor.text.contains("\tchild one\n\tchild two"))
        #expect(h.editor.foldedLines == [])
    }

    @Test func nothingEditsHiddenLinesForAnyRangeOrSelector() throws {
        // 어떤 선택에서 어떤 지우기를 눌러도, 접힌 채로 감춘 줄의 글자가 바뀌지 않는다.
        let selectors = [
            "deleteBackward:", "deleteForward:", "deleteWordBackward:", "deleteWordForward:",
            "deleteToBeginningOfLine:", "deleteToEndOfLine:", "deleteToBeginningOfParagraph:",
            "deleteToEndOfParagraph:", "deleteBackwardByDecomposingPreviousCharacter:",
        ]
        let hidden = "\tchild one\n\tchild two"
        for selector in selectors {
            for location in [2, 3, 26, 27] {
                for length in [0, 1, 23, 24] where location + length <= 31 {
                    let h = try folded()
                    h.editor.selectedRange = NSRange(location: location, length: length)
                    let before = h.editor.selectedRange
                    h.press(Selector(selector))
                    let stillFolded = h.editor.foldedLines == [0]
                    let label = Comment(rawValue: "\(selector) \(before)")
                    if stillFolded {
                        #expect(h.editor.text.contains(hidden), label)
                    } else {
                        // 펴졌다면 그 한 번에 사라진 글자는 줄바꿈과 줄 머리뿐이다.
                        let letters = h.editor.text.filter { !$0.isWhitespace }
                        #expect(letters.contains("childone") && letters.contains("childtwo"), label)
                    }
                }
            }
        }
    }
}
