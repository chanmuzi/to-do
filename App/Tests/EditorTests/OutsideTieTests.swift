import AppKit
import Testing
@testable import Editor

/// 바깥이 끼워 넣은 글이 사용자가 글을 지운 자리(되돌리면 글이 되살아나는 곳)와 꼭 같은 자리에 놓였을 때
/// (D-037). 문서의 끝에서는 되살아나는 글이 바깥의 글 앞에, 맨 앞에서는 뒤에 오고, 가운데에서는 기록을 버린다.
@MainActor
@Suite struct OutsideTieTests {
    @Test func deletionAtTheDocumentEndIsRestoredBeforeTheAppendedLine() throws {
        let h = try EditorHarness("할 일\n메모")
        h.caret(at: h.document.length)
        h.press(NSResponder.backspace)
        h.editor.appendFromOutside("\n[ ] 우유\n")
        h.undo()
        #expect(h.editor.text == "할 일\n메모\n[ ] 우유\n")
        #expect(h.marked == "할 일\n메모|\n[ ] 우유\n")
        h.redo()
        #expect(h.editor.text == "할 일\n메\n[ ] 우유\n")
    }

    /// 앱에서처럼 런 루프 한 차례가 한 단계일 때: 친 글의 끝을 지운 자리에 붙어도 친 단계가 남는다.
    @Test func typingStepSurvivesAnAppendAfterABackspace() async throws {
        let h = try EditorHarness("")
        h.editor.undoManager.groupsByEvent = true
        for character in "메모" {
            h.view.insertText(String(character), replacementRange: h.view.selectedRange())
            try await Task.sleep(for: .milliseconds(2))
        }
        h.view.doCommand(by: NSResponder.backspace)
        try await Task.sleep(for: .milliseconds(2))
        h.editor.appendFromOutside("\n[ ] 우유\n")
        h.undo()
        #expect(h.editor.text == "메모\n[ ] 우유\n")
        #expect(h.editor.undoManager.canUndo)
        h.undo()
        #expect(h.editor.text == "\n[ ] 우유\n")
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        h.redo()
        #expect(h.editor.text == "메\n[ ] 우유\n")
    }

    @Test func redoAtTheDocumentEndInsertsBeforeTheAppendedLine() throws {
        let h = try EditorHarness("가\n나")
        h.caret(at: h.document.length)
        h.type("!")
        h.undo()
        #expect(h.editor.text == "가\n나")
        h.editor.appendFromOutside("\n[ ] 우유\n")
        h.redo()
        #expect(h.editor.text == "가\n나!\n[ ] 우유\n")
        h.undo()
        #expect(h.editor.text == "가\n나\n[ ] 우유\n")
    }

    /// 빈 문서는 끝으로 본다: 되살아나는 글이 바깥의 글 앞에 온다.
    @Test func emptyDocumentCountsAsTheEnd() throws {
        let h = try EditorHarness("메모")
        h.step { h.view.selectAll(nil) }
        h.press(NSResponder.backspace)
        #expect(h.editor.text.isEmpty)
        h.editor.appendFromOutside("[ ] 우유\n")
        h.undo()
        #expect(h.editor.text == "메모[ ] 우유\n")
    }

    @Test func deletionAtTheDocumentStartIsRestoredAfterAPrependedLine() throws {
        let h = try EditorHarness("가나다")
        h.caret(at: 0)
        h.press(NSResponder.forwardDelete)
        h.editor.applyOutsideChange(to: "머리말\n나다")
        h.undo()
        #expect(h.editor.text == "머리말\n가나다")
        #expect(h.marked == "머리말\n|가나다")
    }

    /// 가운데에서는 어느 쪽에 두어도 되살린 글이 바깥이 쓴 줄에 붙을 수 있다. 그 단계와 그보다 오래된 단계를 버린다.
    @Test func tieInTheMiddleDropsTheStepAndOlderOnes() throws {
        let h = try EditorHarness("가나다\n끝")
        h.caret(at: 0)
        h.type("!")
        h.caret(at: 4)
        h.press(NSResponder.backspace)
        h.caret(at: h.document.length)
        h.type("?")
        #expect(h.editor.text == "!가나\n끝?")
        // `다`를 지운 바로 그 자리에 바깥이 글을 끼워 넣는다.
        h.editor.applyOutsideChange(to: "!가나 추가\n끝?")
        h.undo()
        #expect(h.editor.text == "!가나 추가\n끝")
        #expect(!h.editor.undoManager.canUndo)
        // 다시 하기 쪽도 같다: 글을 다시 넣을 자리에 바깥의 글이 끼어들면 그 단계는 버린다.
        let k = try EditorHarness("가나다")
        k.caret(at: 1)
        k.type("!")
        k.undo()
        k.editor.applyOutsideChange(to: "가X나다")
        #expect(!k.editor.undoManager.canRedo)
        #expect(k.editor.text == "가X나다")
    }

    /// 조합 중에 미뤄 둔 변경: 조합하던 글자 앞에 붙인 글은 그 글자가 무엇으로 바뀌든 맨 앞에 들어간다.
    @Test func prependDeferredDuringACompositionAtTheStartStaysInFront() throws {
        let h = try EditorHarness("가나")
        h.step { h.view.selectAll(nil) }
        h.mark("ㅎ")
        h.editor.applyOutsideChange(to: "머리말\nㅎ")
        h.step { h.view.unmarkText() }
        #expect(h.editor.text == "머리말\nㅎ")
        h.undo()
        #expect(h.editor.text == "머리말\n가나")
        // 조합을 그만둬 문서가 비었어도 맨 앞에 붙인 글이다(되살아나는 글이 그 뒤에 온다).
        let k = try EditorHarness("가나")
        k.step { k.view.selectAll(nil) }
        k.mark("ㅎ")
        k.editor.applyOutsideChange(to: "머리말\nㅎ")
        k.mark("")
        #expect(k.editor.text == "머리말\n")
        k.undo()
        #expect(k.editor.text == "머리말\n가나")
        #expect(k.controller.historyDropCount == 0)
    }

    /// 조합 중에 ⌘Z를 눌러도 미뤄 둔 변경과 기록이 어긋나지 않는다.
    @Test func undoWhileComposingWithADeferredChange() throws {
        let h = try EditorHarness("가나")
        h.caret(at: 2)
        h.type("다")
        h.caret(at: 0)
        h.mark("ㅎ")
        h.editor.applyOutsideChange(to: "머리말\nㅎ가나다")
        h.undo()
        #expect(h.editor.text == "머리말\n가나다")
        h.undo()
        #expect(h.editor.text == "머리말\n가나")
        #expect(h.controller.historyDropCount == 0)
    }

    /// 어긋난 단계는 원문을 고치지 않고 기록을 버린다(있어서는 안 되는 경우의 안전장치).
    @Test func aMismatchingStepNeverWrites() throws {
        let h = try EditorHarness("가나다")
        h.caret(at: 3)
        h.type("라")
        h.expectsReplayMismatch = true
        // 기록이 가리키는 자리의 글을 기록 모르게 바꾼다.
        h.controller.history.undoStack[0].edits[0].new = "마"
        h.undo()
        #expect(h.editor.text == "가나다라")
        #expect(h.replayMismatches.count == 1)
        #expect(!h.editor.undoManager.canUndo)
        #expect(!h.editor.undoManager.canRedo)
    }
}

@Suite struct UndoHistoryLimitTests {
    @Test func historyKeepsTheNewestThousandSteps() {
        var history = UndoHistory()
        for index in 0..<(UndoHistory.limit + 250) {
            let caret = NSRange(location: index, length: 0)
            history.open = UndoRecord(edits: [UndoEdit(location: index, old: "", new: "\(index % 10)")], selectionBefore: caret, selectionAfter: caret)
            history.close(selectionAfter: NSRange(location: index + 1, length: 0), coalescesTyping: false)
        }
        #expect(history.undoStack.count == UndoHistory.limit)
        #expect(history.undoStack.first?.edits[0].location == 250)
        #expect(history.undoStack.last?.edits[0].location == UndoHistory.limit + 249)
    }

    @Test func tieRulesOnThePureHistory() {
        func deletion(at location: Int) -> UndoRecord {
            let caret = NSRange(location: location, length: 0)
            return UndoRecord(edits: [UndoEdit(location: location, old: "x", new: "")], selectionBefore: caret, selectionAfter: caret)
        }
        // 끝: 되살아날 글은 제자리(바깥의 글 앞).
        var end = UndoHistory()
        end.undoStack = [deletion(at: 5)]
        end.shift(outside: NSRange(location: 5, length: 0), delta: 3, documentLength: 5)
        #expect(end.undoStack.map { $0.edits[0].location } == [5])
        // 맨 앞: 바깥의 글 뒤로.
        var start = UndoHistory()
        start.undoStack = [deletion(at: 0)]
        start.shift(outside: NSRange(location: 0, length: 0), delta: 3, documentLength: 5)
        #expect(start.undoStack.map { $0.edits[0].location } == [3])
        // 가운데: 버린다. 더 최근 단계는 남는다.
        var middle = UndoHistory()
        middle.undoStack = [deletion(at: 1), deletion(at: 2), deletion(at: 4)]
        middle.shift(outside: NSRange(location: 2, length: 0), delta: 3, documentLength: 5)
        #expect(middle.undoStack.map { $0.edits[0].location } == [7])
        // 길이가 있는 범위를 바꾼 것은 같은 자리에서 만나는 경우가 아니다.
        var replaced = UndoHistory()
        replaced.undoStack = [deletion(at: 2), deletion(at: 4)]
        replaced.shift(outside: NSRange(location: 2, length: 2), delta: 1, documentLength: 5)
        #expect(replaced.undoStack.map { $0.edits[0].location } == [2, 5])
    }
}
