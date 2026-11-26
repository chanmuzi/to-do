import AppKit
import Testing
@testable import Editor

/// 접힌 토글이 편집, 되돌리기, 원문 넣기를 따라가는지.
@MainActor
@Suite struct FoldEditingTests {
    private func loaded(_ text: String, folded: Set<Int>) throws -> EditorHarness {
        let h = try EditorHarness()
        h.editor.load(text: text, foldedLines: folded)
        return h
    }

    // MARK: 들여쓰기

    @Test func tabOnAFoldedToggleTakesItsHiddenChildrenAlong() throws {
        let h = try loaded("- a\n+ T\n\tc1\n\tc2\nafter", folded: [1])
        h.caret(atEndOfLine: 1)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "- a\n\t+ T\n\t\tc1\n\t\tc2\nafter")
        #expect(h.editor.foldedLines == [1])
        #expect(h.document.lines[1].subtreeEnd == 4)
        #expect(h.editor.selectedRange == NSRange(location: h.document.lines[1].end, length: 0))
        h.press(NSResponder.backtab)
        #expect(h.editor.text == "- a\n+ T\n\tc1\n\tc2\nafter")
        #expect(h.editor.foldedLines == [1])
        // 줄 번호가 그대로이므로 알릴 것이 없다.
        #expect(h.foldChanges.isEmpty)
    }

    @Test func tabOverSeveralLinesKeepsAFoldInTheMiddle() throws {
        // 들여 쓴 줄은 부모 항목(`- p`) 아래에만 놓인다(D-043).
        let h = try loaded("- p\n- a\n+ T\n\tc1\n\tc2\nafter", folded: [2])
        let start = h.document.lines[1].contentStart
        h.editor.selectedRange = NSRange(location: start, length: h.document.lines[2].end - start)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "- p\n\t- a\n\t+ T\n\t\tc1\n\t\tc2\nafter")
        #expect(h.editor.foldedLines == [2])
        h.undo()
        #expect(h.editor.text == "- p\n- a\n+ T\n\tc1\n\tc2\nafter")
        #expect(h.editor.foldedLines == [2])
    }

    @Test func tabOverEverythingIndentsHiddenLinesToo() throws {
        let h = try loaded("- p\n+ T\n\tc1\nz", folded: [1])
        let start = h.document.lines[1].start
        h.editor.selectedRange = NSRange(location: start, length: h.document.length - start)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "- p\n\t+ T\n\t\tc1\n\tz")
        #expect(h.editor.foldedLines == [1])
    }

    @Test func returnOnEmptyNestedFoldedToggleRemovesMarkerAndAdoptsChildren() throws {
        let h = try loaded("- a\n\t+ \n\t\tc1\nz", folded: [1])
        h.caret(atEndOfLine: 1)
        h.press(NSResponder.newline)
        #expect(h.editor.text == "- a\n\t\n\tc1\nz")
        #expect(h.editor.foldedLines.isEmpty)
        h.undo()
        #expect(h.editor.text == "- a\n\t+ \n\t\tc1\nz")
        #expect(h.editor.foldedLines == [1])
    }

    // MARK: 줄 번호 따라가기

    @Test func deletingTheLineAboveKeepsTheToggleFolded() throws {
        let h = try loaded("memo\n+ T\n\tc1\n\tc2\nz", folded: [1])
        h.editor.selectedRange = NSRange(location: 0, length: 5)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "+ T\n\tc1\n\tc2\nz")
        #expect(h.editor.foldedLines == [0])
        #expect(h.foldChanges == [[0]])
        h.undo()
        #expect(h.editor.text == "memo\n+ T\n\tc1\n\tc2\nz")
        #expect(h.editor.foldedLines == [1])
        #expect(h.foldChanges == [[0], [1]])
    }

    @Test func replacingTheLineAboveKeepsTheToggleFolded() throws {
        let h = try loaded("memo\n+ T\n\tc1\n\tc2\nz", folded: [1])
        h.editor.selectedRange = NSRange(location: 0, length: 5)
        h.type("x")
        // 토글이 아니게 됐으므로 접힘이 없어지고, 부모를 잃은 하위 줄은 함께 나온다(D-043).
        #expect(h.editor.text == "x+ T\nc1\nc2\nz")
        #expect(h.editor.foldedLines == [])
        h.undo()
        #expect(h.editor.foldedLines == [1])
    }

    @Test func pastingLinesAboveShiftsTheFold() throws {
        let h = try loaded("memo\n+ T\n\tc1\nz", folded: [1])
        h.caret(at: 0)
        h.step { h.view.insertText("a\nb\n", replacementRange: h.view.selectedRange()) }
        #expect(h.editor.foldedLines == [3])
        h.undo()
        #expect(h.editor.foldedLines == [1])
        h.redo()
        #expect(h.editor.text == "a\nb\nmemo\n+ T\n\tc1\nz")
        #expect(h.editor.foldedLines == [3])
    }

    // MARK: 되돌리기

    @Test func undoAfterMovingAFoldedToggleRestoresTheFold() throws {
        let source = "+ A\n+ T\n\tchild\nz"
        let h = try loaded(source, folded: [1])
        h.caret(atEndOfLine: 1)
        h.perform(.moveLineUp)
        #expect(h.editor.text == "+ T\n\tchild\n+ A\nz")
        #expect(h.editor.foldedLines == [0])
        h.undo()
        #expect(h.editor.text == source)
        #expect(h.editor.foldedLines == [1])
        h.redo()
        #expect(h.editor.text == "+ T\n\tchild\n+ A\nz")
        #expect(h.editor.foldedLines == [0])
        h.undo()
        #expect(h.editor.foldedLines == [1])
        // 바뀔 때마다 한 번씩만 알린다.
        #expect(h.foldChanges == [[0], [1], [0], [1]])
        // 되돌린 뒤에도 감춘 줄은 접힌 채다(선택이 그 안에 남지 않는다).
        let selection = h.editor.selectedRange
        for position in [selection.location, NSMaxRange(selection)] {
            #expect(FoldState.foldRoot(of: h.document.lineIndex(at: position), in: h.document, folded: [1]) == nil)
        }
    }

    @Test func undoRestoresAFoldLostWithItsToggle() throws {
        let source = "+ T\n\tc1\nz"
        let h = try loaded(source, folded: [0])
        // 토글 기호를 지우면 접힘이 없어진다.
        h.caret(at: 2)
        h.press(NSResponder.backspace)
        // 부모를 잃은 하위 줄은 함께 나온다(D-043).
        #expect(h.editor.text == "T\nc1\nz")
        #expect(h.editor.foldedLines == [])
        h.undo()
        #expect(h.editor.text == source)
        #expect(h.editor.foldedLines == [0])
    }

    @Test func undoOfAnEditInsideAFoldedToggleUnfoldsIt() throws {
        let h = try loaded("+ T\n\tc1\nz", folded: [])
        h.caret(atEndOfLine: 1)
        h.type("!")
        h.editor.foldedLines = [0]
        h.undo()
        // 감춘 줄이 바뀌었으므로 보이게 편다(D-018).
        #expect(h.editor.text == "+ T\n\tc1\nz")
        #expect(h.editor.foldedLines == [])
        #expect(h.foldChanges == [[]])
    }

    // MARK: 원문과 접힘 넣기

    @Test func loadTakesTextAndFoldsTogether() throws {
        let h = try EditorHarness()
        // 원문보다 먼저 넣은 접힘은 토글이 없어 남지 않는다.
        h.editor.foldedLines = [1]
        h.editor.text = "memo\n+ T\n\tc1"
        #expect(h.editor.foldedLines == [])
        h.editor.load(text: "memo\n+ T\n\tc1\nz", foldedLines: [1, 3, 9])
        #expect(h.editor.foldedLines == [1])
        #expect(h.editor.text == "memo\n+ T\n\tc1\nz")
        #expect(h.foldChanges.isEmpty)
        #expect(h.changes.isEmpty)
        #expect(!h.editor.undoManager.canUndo)
        // 같은 글이면 접힘만 바꾸고 되돌리기 기록은 그대로다.
        h.caret(at: 4)
        h.type("!")
        h.editor.load(text: "memo!\n+ T\n\tc1\nz", foldedLines: [])
        #expect(h.editor.foldedLines == [])
        #expect(h.editor.undoManager.canUndo)
        #expect(h.foldChanges.isEmpty)
    }

    @Test func settingTextThatDropsAFoldReportsItOnceRightAway() throws {
        let h = try loaded("memo\n+ T\n\tc1", folded: [1])
        h.editor.text = "memo\nplain\n\tc1"
        #expect(h.editor.foldedLines == [])
        #expect(h.foldChanges == [[]])
        // 다음 입력에서 뒤늦게 다시 알리지 않는다.
        h.caret(at: 4)
        h.type("!")
        #expect(h.foldChanges == [[]])
        // 접힘이 그대로 남는 글이면 알리지 않는다.
        h.editor.load(text: "+ T\n\tc1", foldedLines: [0])
        h.editor.text = "+ T2\n\tc1"
        #expect(h.editor.foldedLines == [0])
        #expect(h.foldChanges == [[]])
    }

    @Test func foldChangeIsReportedOnlyWhenTheSetChanges() throws {
        let h = try loaded("+ T\n\tc1\nz", folded: [])
        h.perform(.unfold)
        h.caret(atEndOfLine: 0)
        h.perform(.fold)
        h.perform(.fold)
        #expect(h.foldChanges == [[0]])
        // 아래를 고쳐도 줄 번호가 그대로면 알리지 않는다.
        h.caret(at: h.document.length)
        h.type("!")
        #expect(h.foldChanges == [[0]])
    }
}

@Suite struct FoldRemapTests {
    private func remap(_ text: String, folded: Set<Int>, _ edit: TextEdit) -> Set<Int> {
        let old = MarkdownDocument(text)
        let new = MarkdownDocument(edit.applied(to: text))
        let delta = edit.replacement.utf16.count - edit.range.length
        let edited = NSRange(location: edit.range.location, length: edit.replacement.utf16.count)
        return FoldState.remapped(folded, old: old, new: new, editedRange: edited, delta: delta)
    }

    @Test func foldFollowsTheFirstCharacterOfItsLine() {
        let text = "memo\n+ T\n\tc1\nz"
        // 윗줄 전체(줄바꿈까지)를 지우거나 바꿔도 토글을 따라간다.
        #expect(remap(text, folded: [1], TextEdit(range: NSRange(location: 0, length: 5), replacement: "", selection: NSRange())) == [0])
        #expect(remap(text, folded: [1], TextEdit(range: NSRange(location: 0, length: 5), replacement: "a\nb\n", selection: NSRange())) == [2])
        // 윗줄과 합쳐지면 토글이 아니다.
        #expect(remap(text, folded: [1], TextEdit(range: NSRange(location: 4, length: 1), replacement: "", selection: NSRange())) == [])
        // 빈 윗줄과 합쳐지면 그 줄이 토글이 된다.
        #expect(remap("\n+ T\n\tc1", folded: [1], TextEdit(range: NSRange(location: 0, length: 1), replacement: "", selection: NSRange())) == [0])
        // 줄 맨 앞에 탭을 끼우면 여전히 그 줄이 토글이다.
        #expect(remap(text, folded: [1], .insert("\t", replacing: NSRange(location: 5, length: 0))) == [1])
        // 줄의 첫 글자가 바뀐 범위 한가운데에 있었으면 버린다.
        #expect(remap(text, folded: [1], TextEdit(range: NSRange(location: 2, length: 6), replacement: "+ X", selection: NSRange())) == [])
    }

    @Test func brokenRootsAreTheFoldsWhoseHiddenLinesTheRangeTouches() {
        let doc = MarkdownDocument("+ T\n\tchild one\n\tchild two\nafter")
        func broken(_ location: Int, _ length: Int) -> Set<Int> {
            FoldState.brokenRoots(by: NSRange(location: location, length: length), in: doc, folded: [0])
        }
        // 제목 줄과 다음 줄 안의 편집은 괜찮다.
        #expect(broken(3, 0) == [])
        #expect(broken(2, 1) == [])
        #expect(broken(26, 0) == [])
        #expect(broken(26, 5) == [])
        // 감춘 줄의 글자, 그 앞뒤 줄바꿈, 통째로 덮는 범위.
        #expect(broken(3, 1) == [0])
        #expect(broken(4, 0) == [0])
        #expect(broken(25, 0) == [0])
        #expect(broken(25, 1) == [0])
        #expect(broken(10, 3) == [0])
        #expect(broken(0, 31) == [0])
        // 접히지 않았으면 해당 없다.
        #expect(FoldState.brokenRoots(by: NSRange(location: 4, length: 3), in: doc, folded: []) == [])
        // 감춘 줄이 문서 끝이면 문서 끝도 감춘 줄 안이다.
        let tail = MarkdownDocument("+ T\n\tc")
        #expect(FoldState.brokenRoots(by: NSRange(location: 6, length: 0), in: tail, folded: [0]) == [0])
    }
}

extension FoldEditingTests {
    @Test func newToggleFoldsAndIndentRevealsItsChild() throws {
        let h = try EditorHarness.at(">|제목\n다음")
        h.type(" ")
        #expect(h.editor.foldedLines == [0])
        h.caret(atEndOfLine: 1)
        h.perform(.indent)
        #expect(h.editor.foldedLines.isEmpty)
        #expect(h.editor.text == "+ 제목\n\t다음")
        h.undo()
        #expect(h.editor.foldedLines == [0])
        let parent = try EditorHarness.at("- >|제목\n\t자식")
        parent.type(" ")
        #expect(parent.editor.text == "+ 제목\n\t자식")
        #expect(parent.editor.foldedLines.isEmpty)
    }
}

extension FoldEditingTests {
    @Test func movingAndInsertingInsideAClosedToggleRevealTheDestination() throws {
        let h = try EditorHarness.at("부모\n\t|옮길 줄\n+ 토글")
        h.editor.foldedLines = [2]
        h.controller.selectBlocks()
        h.perform(.moveSelectedBlockDown)
        #expect(h.editor.text == "부모\n+ 토글\n\t옮길 줄")
        #expect(h.editor.foldedLines.isEmpty)

        h.controller.clearBlocks()
        h.caret(atEndOfLine: 1)
        h.perform(.toggleDone)
        h.controller.selectBlocks()
        h.step { h.controller.pasteSource("붙인 줄", inside: true) }
        #expect(h.editor.text == "부모\n+ 토글\n\t붙인 줄\n\t옮길 줄")
        #expect(h.editor.foldedLines.isEmpty)
    }

    @Test func emptyItemReturnTwiceLeavesToggle() throws {
        for marker in ["[ ] ", "- ", "+ ", "> ", "+ ## "] {
            let h = try EditorHarness.at("+ 부모\n\t" + marker + "|")
            h.press(NSResponder.newline)
            #expect(h.marked == "+ 부모\n\t|")
            h.press(NSResponder.newline)
            #expect(h.marked == "+ 부모\n|")
            h.undo()
            #expect(h.marked == "+ 부모\n\t|")
        }
    }
}

extension FoldEditingTests {
    @Test func returnOnUnrecordedEmptyToggleCreatesClosedSibling() throws {
        for marker in ["+ ", "+ ## "] {
            let h = try EditorHarness.at(marker + "제목|")
            h.press(NSResponder.newline)
            #expect(h.marked == marker + "제목\n" + marker + "|")
            #expect(h.controller.currentKeys().allSatisfy { $0.isFolded && !$0.showsEmptyToggleHint })
            h.undo()
            #expect(h.marked == marker + "제목|")
            #expect(h.editor.openedEmptyToggleLines.isEmpty)
        }
    }
}
