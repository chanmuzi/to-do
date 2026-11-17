import AppKit
import Testing
@testable import Editor

/// 바깥(이 편집기가 아닌 쪽)이 원문을 바꿨을 때 달라진 부분만 넣는다(`applyOutsideChange`).
@Suite struct OutsideEditTests {
    private func edit(_ old: String, _ new: String) -> OutsideEdit? { OutsideEdit(from: old, to: new) }

    @Test func onlyTheDifferingMiddleIsReplaced() throws {
        #expect(edit("같은 글", "같은 글") == nil)
        let append = try #require(edit("처음", "처음\n둘째"))
        #expect(append.range == NSRange(location: 2, length: 0))
        #expect(append.replacement == "\n둘째")
        // 끝의 빈 줄을 다듬고 붙인 글: 마지막 줄바꿈 앞에 끼워 넣은 것으로 읽힌다.
        let trimmed = try #require(edit("첫 줄\n둘째 줄\n\n", "첫 줄\n둘째 줄\n[ ] 우유\n"))
        #expect(trimmed.range == NSRange(location: 9, length: 0))
        #expect(trimmed.replacement == "[ ] 우유")
        #expect(trimmed.applied(to: "첫 줄\n둘째 줄\n\n") == "첫 줄\n둘째 줄\n[ ] 우유\n")
        let middle = try #require(edit("가 나 다", "가 라마 다"))
        #expect(middle.range == NSRange(location: 2, length: 1))
        #expect(middle.replacement == "라마")
        #expect(middle.applied(to: "가 나 다") == "가 라마 다")
        let removed = try #require(edit("가나다", "가다"))
        #expect(removed.range == NSRange(location: 1, length: 1))
        #expect(removed.replacement.isEmpty)
    }

    @Test func surrogatePairsAreNeverSplit() throws {
        // 두 이모지는 앞쪽 절반이 같다. 쌍의 한가운데에서 자르지 않는다.
        let change = try #require(edit("a😀b", "a😁b"))
        #expect(change.range == NSRange(location: 1, length: 2))
        #expect(change.replacement == "😁")
    }

    @Test func positionsFollowTheChange() throws {
        let change = try #require(edit("가 나 다", "가 라마 다"))
        #expect(change.moved(1, sticksToEnd: false) == 1)
        #expect(change.moved(2, sticksToEnd: false) == 2)
        #expect(change.moved(3, sticksToEnd: false) == 4)
        #expect(change.moved(5, sticksToEnd: false) == 6)
        let insert = try #require(edit("처음", "처음둘째"))
        #expect(insert.moved(2, sticksToEnd: false) == 2)
        #expect(insert.moved(2, sticksToEnd: true) == 4)
    }

    @Test func aDeferredEditFollowsLaterEdits() throws {
        var change = try #require(edit("처음\n끝", "처음\n끝\n붙임"))
        // 앞쪽에 한 글자가 들어갔다(조합 중인 글자).
        change.shift(editedRange: NSRange(location: 2, length: 1), delta: 1)
        #expect(change.range == NSRange(location: 5, length: 0))
        // 같은 자리에서 조합 글자가 바뀌기만 했다.
        change.shift(editedRange: NSRange(location: 2, length: 1), delta: 0)
        #expect(change.range == NSRange(location: 5, length: 0))
        #expect(change.applied(to: "처음한\n끝") == "처음한\n끝\n붙임")
    }
}

@MainActor
@Suite struct OutsideChangeTests {
    /// 빈 마지막 줄에 커서를 둔 채 바깥이 그 줄에 글을 붙였다. 커서를 제자리에 두면 이어 친 글이
    /// 붙은 줄의 머리에 끼어든다(`이어서[ ] 우유`). 커서는 붙은 글 뒤의 새 빈 줄로 간다.
    @Test func caretOnTheEmptyLastLineMovesPastTextAppendedOntoThatLine() throws {
        let h = try EditorHarness("첫 줄\n")
        h.caret(at: 4)
        h.editor.appendFromOutside("[ ] 우유\n")
        #expect(h.marked == "첫 줄\n[ ] 우유\n|")
        #expect(h.changes.isEmpty)
        h.type("이어서")
        #expect(h.editor.text == "첫 줄\n[ ] 우유\n이어서")
        #expect(h.document.lines.map(\.kind) == [.paragraph, .todo(done: false), .paragraph])
        // ⌘Z는 사용자가 친 글만 되돌린다.
        for _ in 0..<3 { h.undo() }
        #expect(h.editor.text == "첫 줄\n[ ] 우유\n")
    }

    /// 붙은 글이 줄바꿈으로 끝나지 않으면 커서는 그 줄 끝에 놓이고, 이어 치는 글은 새 줄에서 시작한다.
    @Test func typingAfterAnAppendWithoutATrailingNewlineStartsANewLine() throws {
        let h = try EditorHarness("첫 줄\n")
        h.caret(at: 4)
        h.editor.appendFromOutside("[ ] 우유")
        #expect(h.marked == "첫 줄\n[ ] 우유|")
        h.type("이")
        #expect(h.marked == "첫 줄\n[ ] 우유\n이|")
        h.type("어")
        #expect(h.marked == "첫 줄\n[ ] 우유\n이어|")
        h.undo()
        h.undo()
        #expect(h.editor.text == "첫 줄\n[ ] 우유")

        // 한글 조합으로 시작해도 같다. 조합은 끊기지 않는다.
        let k = try EditorHarness("")
        k.editor.appendFromOutside("[ ] 우유")
        #expect(k.marked == "[ ] 우유|")
        k.mark("ㅎ")
        #expect(k.view.hasMarkedText())
        #expect(k.editor.text == "[ ] 우유\nㅎ")
        k.commit("한")
        #expect(k.editor.text == "[ ] 우유\n한")

        // 커서를 옮겼다가 돌아오면 그 줄에 이어 쓰겠다는 뜻으로 본다.
        let m = try EditorHarness("")
        m.editor.appendFromOutside("[ ] 우유")
        m.press(NSResponder.left)
        m.press(NSResponder.right)
        m.type("!")
        #expect(m.editor.text == "[ ] 우유!")
    }

    /// 붙은 글이 줄바꿈으로 시작하면 커서의 줄은 그대로다. 커서는 제자리에 남아 그 줄을 이어 쓴다.
    @Test func caretStaysWhenItsOwnLineIsUntouched() throws {
        let h = try EditorHarness("쓰던 줄")
        h.caret(at: 4)
        h.editor.appendFromOutside("\n[ ] 우유\n")
        #expect(h.marked == "쓰던 줄|\n[ ] 우유\n")
        h.type("!")
        #expect(h.editor.text == "쓰던 줄!\n[ ] 우유\n")
        // 문서 끝이 아닌 커서와 선택은 언제나 제자리다.
        let k = try EditorHarness("가나다\n")
        k.place(at: 1, length: 2)
        k.editor.appendFromOutside("[ ] 우유\n")
        #expect(k.marked == "가|나다|\n[ ] 우유\n")
    }

    /// 끝의 빈 줄을 다듬고 붙인 변경(끝에 붙기만 한 것이 아니다): 통째로 넣지 않으므로 되돌리기 기록이
    /// 남고, 빈 마지막 줄의 커서는 바깥이 쓴 줄 속이 아니라 그 뒤의 빈 줄에 놓인다.
    @Test func trailingBlankLineTrimmedThenAppendedKeepsUndoAndTheCaretOutOfTheForeignLine() throws {
        let h = try EditorHarness("첫 줄\n둘째\n\n")
        h.caret(at: 3)
        h.type("!")
        #expect(h.editor.text == "첫 줄!\n둘째\n\n")
        h.caret(at: h.document.length)
        let reported = h.changes.count
        h.step { h.editor.applyOutsideChange(to: "첫 줄!\n둘째\n[ ] 우유\n") }
        #expect(h.marked == "첫 줄!\n둘째\n[ ] 우유\n|")
        #expect(h.changes.count == reported)
        #expect(h.editor.undoManager.canUndo)
        h.type("이어서")
        #expect(h.editor.text == "첫 줄!\n둘째\n[ ] 우유\n이어서")
        // 되돌리기: 친 글, 그다음 예전에 친 글. 바깥의 변경은 되돌리기에 없다(붙은 줄이 그대로 남는다).
        for _ in 0..<3 { h.undo() }
        #expect(h.editor.text == "첫 줄!\n둘째\n[ ] 우유\n")
        h.undo()
        #expect(h.editor.text == "첫 줄\n둘째\n[ ] 우유\n")
        #expect(!h.editor.undoManager.canUndo)
        h.editor.flushPendingChange()
        #expect(h.changes.last == "첫 줄\n둘째\n[ ] 우유\n")
        h.redo()
        #expect(h.marked == "첫 줄!|\n둘째\n[ ] 우유\n")
    }

    @Test func changeInTheMiddleKeepsSelectionFoldsAndReportsNothing() throws {
        let h = try EditorHarness("머리\n+ 토글\n\t안\n가운데 줄\n꼬리")
        h.editor.foldedLines = [1]
        let tail = h.document.lines[4]
        h.place(at: tail.start + 1, length: 1)
        h.step { h.editor.applyOutsideChange(to: "머리\n+ 토글\n\t안\n가운데를 고친 줄\n꼬리") }
        #expect(h.editor.foldedLines == [1])
        #expect(h.marked == "머리\n+ 토글\n\t안\n가운데를 고친 줄\n꼬|리|")
        // 위에 줄이 끼어들면 접힘은 줄을 따라 옮겨지고, 선택은 같은 글자를 가리킨다.
        h.step { h.editor.applyOutsideChange(to: "새 줄\n머리\n+ 토글\n\t안\n가운데를 고친 줄\n꼬리") }
        #expect(h.editor.text == "새 줄\n머리\n+ 토글\n\t안\n가운데를 고친 줄\n꼬리")
        #expect(h.editor.foldedLines == [2])
        #expect(h.marked == "새 줄\n머리\n+ 토글\n\t안\n가운데를 고친 줄\n꼬|리|")
        #expect(h.changes.isEmpty)
        // 커서가 바뀐 부분 안에 있었으면 바뀐 부분 뒤로 간다.
        let k = try EditorHarness("가 나나나 다")
        k.place(at: 4)
        k.step { k.editor.applyOutsideChange(to: "가 라 다") }
        #expect(k.marked == "가 라| 다")
        // 같은 글이면 아무것도 하지 않는다.
        k.editor.applyOutsideChange(to: "가 라 다")
        #expect(k.marked == "가 라| 다")
    }

    @Test func changeTouchingAFoldedSubtreeUnfoldsIt() throws {
        let h = try EditorHarness("+ 토글\n\t안\n밖")
        h.editor.foldedLines = [0]
        h.caret(atEndOfLine: 2)
        h.step { h.editor.applyOutsideChange(to: "+ 토글\n\t안을 고침\n밖") }
        #expect(h.editor.text == "+ 토글\n\t안을 고침\n밖")
        #expect(h.editor.foldedLines.isEmpty)
    }

    @Test func compositionIsKeptAndTheChangeIsNeverMissingFromTheSource() throws {
        let h = try EditorHarness("처음\n끝\n\n")
        h.caret(at: 2)
        h.mark("ㅎ")
        let marked = h.view.markedRange()
        // 조합하는 자리와 겹치지 않는 변경: 화면에 넣는 일만 미룬다.
        h.editor.applyOutsideChange(to: "처음ㅎ\n끝\n[ ] 우유\n")
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == marked)
        #expect(h.view.string == "처음ㅎ\n끝\n\n")
        #expect(h.editor.text == "처음ㅎ\n끝\n[ ] 우유\n")
        h.mark("하")
        #expect(h.changes.last == "처음하\n끝\n[ ] 우유\n")
        h.commit("한")
        #expect(!h.view.hasMarkedText())
        #expect(h.view.string == "처음한\n끝\n[ ] 우유\n")
        #expect(h.marked == "처음한|\n끝\n[ ] 우유\n")
        #expect(h.changes.last == "처음한\n끝\n[ ] 우유\n")

        // 조합 중인 글자를 덮는 변경은 지킬 수 없다. 조합을 끝내고 넣는다(원문은 바깥의 글과 같아진다).
        let k = try EditorHarness("처음")
        k.caret(at: 2)
        k.mark("ㅎ")
        k.step { k.editor.applyOutsideChange(to: "다른 글") }
        #expect(!k.view.hasMarkedText())
        #expect(k.editor.text == "다른 글")
    }

    @Test func lineEndingsAreNormalised() throws {
        let h = try EditorHarness("가\n")
        h.editor.applyOutsideChange(to: "가\r\n나\r\n")
        #expect(h.editor.text == "가\n나\n")
    }
}
