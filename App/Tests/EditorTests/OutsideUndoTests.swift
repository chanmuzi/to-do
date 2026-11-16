import AppKit
import Testing
@testable import Editor

/// 바깥(빠른 캡처 등)이 바꾼 글은 사용자의 ⌘Z로 되돌려지지 않는다. 사용자의 되돌리기 기록은 그 변경을
/// 건너 제자리에 남는다(D-037).
@MainActor
@Suite struct OutsideUndoTests {
    @Test func undoNeverRemovesTheOutsideLine() throws {
        let h = try EditorHarness("첫 줄\n끝")
        h.caret(at: 3)
        h.type("!")
        let reported = h.changes.count
        h.editor.applyOutsideChange(to: "첫 줄!\n[ ] 캡처한 줄\n끝")
        #expect(h.changes.count == reported)
        h.undo()
        // `!`만 지워지고 바깥이 넣은 줄은 남는다. 사용자의 편집으로 알리는 글에도 그 줄이 들어 있다.
        #expect(h.editor.text == "첫 줄\n[ ] 캡처한 줄\n끝")
        h.editor.flushPendingChange()
        #expect(h.changes.last == "첫 줄\n[ ] 캡처한 줄\n끝")
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        #expect(h.marked == "첫 줄!|\n[ ] 캡처한 줄\n끝")
    }

    @Test func earlierEditsLandInTheRightPlaceAfterAnOutsideChangeAboveThem() throws {
        let h = try EditorHarness("머리\n가운데\n꼬리")
        h.caret(at: h.document.lines[2].end)
        h.type("1")
        h.caret(at: h.document.lines[1].end)
        h.type("2")
        // 사용자가 고친 두 자리보다 앞에 줄이 끼어든다.
        h.editor.applyOutsideChange(to: "머리\n새 줄 하나\n새 줄 둘\n가운데2\n꼬리1")
        h.undo()
        #expect(h.editor.text == "머리\n새 줄 하나\n새 줄 둘\n가운데\n꼬리1")
        h.undo()
        #expect(h.editor.text == "머리\n새 줄 하나\n새 줄 둘\n가운데\n꼬리")
        h.redo()
        h.redo()
        #expect(h.editor.text == "머리\n새 줄 하나\n새 줄 둘\n가운데2\n꼬리1")
    }

    @Test func redoHistorySurvivesAnOutsideChange() throws {
        let h = try EditorHarness("가\n나")
        h.caret(at: 3)
        h.type("!")
        h.undo()
        h.editor.applyOutsideChange(to: "앞줄\n가\n나")
        h.redo()
        #expect(h.editor.text == "앞줄\n가\n나!")
    }

    /// 바깥의 변경이 사용자가 고친 자리에 겹치면 그 단계와 그보다 오래된 단계는 버린다(범위가 어긋난 채로
    /// 되돌리는 것보다 낫다). 그 뒤의 단계는 남는다.
    @Test func historyThatOverlapsTheOutsideChangeIsDropped() throws {
        let h = try EditorHarness("가나다\n끝")
        h.caret(at: 3)
        h.paste("XYZ")
        h.caret(at: h.document.length)
        h.type("!")
        // 사용자가 한 번에 넣은 `XYZ`의 한가운데를 바깥이 고친다.
        h.editor.applyOutsideChange(to: "가나다X바깥YZ\n끝!")
        h.undo()
        #expect(h.editor.text == "가나다X바깥YZ\n끝")
        #expect(!h.editor.undoManager.canUndo)
        // 따로 친 두 글자 사이에 끼어든 글은 겹치지 않는다. 두 글자 모두 되돌릴 수 있다.
        let between = try EditorHarness("가나다")
        between.caret(at: 3)
        between.type("XY")
        between.editor.applyOutsideChange(to: "가나다X바깥Y")
        between.undo()
        between.undo()
        #expect(between.editor.text == "가나다바깥")
        // 통째로 다른 글: 기록이 모두 사라진다.
        let k = try EditorHarness("처음")
        k.caret(at: 2)
        k.type("!")
        k.editor.applyOutsideChange(to: "다른 프로그램이 고친 글")
        #expect(k.editor.text == "다른 프로그램이 고친 글")
        #expect(!k.editor.undoManager.canUndo)
    }

    @Test func undoOfAQuickCaptureDoesNotDeleteTheCapturedTodo() throws {
        let h = try EditorHarness("메모\n")
        h.caret(at: h.document.length)
        h.type("x")
        h.editor.appendFromOutside("\n[ ] 우유")
        h.undo()
        #expect(h.editor.text == "메모\n\n[ ] 우유")
        #expect(!h.editor.undoManager.canUndo)
    }

    /// 줄바꿈 없이 붙은 글 뒤에서 "이어 치는 글은 새 줄에서"는 잇달아 붙는 글에도 이어진다.
    @Test func caretRuleHoldsAcrossConsecutiveAppends() throws {
        let h = try EditorHarness("메모\n")
        h.caret(at: h.document.length)
        h.editor.appendFromOutside("[ ] 우유")
        h.editor.appendFromOutside("\n[ ] 빵")
        #expect(h.marked == "메모\n[ ] 우유\n[ ] 빵|")
        h.type("x")
        #expect(h.editor.text == "메모\n[ ] 우유\n[ ] 빵\nx")
        // 한글 조합으로 이어 써도 같다.
        let k = try EditorHarness("메모\n")
        k.caret(at: k.document.length)
        k.editor.appendFromOutside("[ ] 우유")
        k.editor.appendFromOutside("\n[ ] 빵\n[ ] 달걀")
        k.mark("ㅎ")
        k.commit("하")
        #expect(k.editor.text == "메모\n[ ] 우유\n[ ] 빵\n[ ] 달걀\n하")
    }
}

/// 되돌리기 기록의 위치 옮기기(순수 계산).
@Suite struct UndoHistoryTests {
    private func record(_ location: Int, _ old: String, _ new: String) -> UndoRecord {
        let caret = NSRange(location: location, length: 0)
        return UndoRecord(edits: [UndoEdit(location: location, old: old, new: new)], selectionBefore: caret, selectionAfter: caret)
    }

    @Test func recordsBeforeAndAfterTheOutsideChangeAreShifted() {
        var history = UndoHistory()
        history.undoStack = [record(2, "", "ab"), record(10, "x", "")]
        history.redoStack = [record(20, "", "z")]
        // 위치 5에 세 글자가 끼어든다.
        history.shift(outside: NSRange(location: 5, length: 0), delta: 3, documentLength: 40)
        #expect(history.undoStack.map { $0.edits[0].location } == [2, 13])
        #expect(history.redoStack.map { $0.edits[0].location } == [23])
    }

    @Test func overlappingRecordAndOlderOnesAreDropped() {
        var history = UndoHistory()
        history.undoStack = [record(0, "", "오래된"), record(10, "", "abcd"), record(30, "", "새")]
        history.shift(outside: NSRange(location: 11, length: 2), delta: 0, documentLength: 40)
        #expect(history.undoStack.map { $0.edits[0].new } == ["새"])
    }

    @Test func typingIsCoalescedOnlyWhenItContinues() {
        var history = UndoHistory()
        func type(_ text: String, at location: Int) {
            var typed = record(location, "", text)
            typed.isTyping = true
            history.open = typed
            history.close(selectionAfter: NSRange(location: location + text.utf16.count, length: 0), coalescesTyping: true)
        }
        type("가", at: 0)
        type("나", at: 1)
        #expect(history.undoStack.map { $0.edits[0].new } == ["가나"])
        // 낱말 사이의 공백에서 끊는다. 다른 자리에서 친 글자도 새 단계다.
        type(" ", at: 2)
        type("다", at: 3)
        type("라", at: 0)
        #expect(history.undoStack.map { $0.edits[0].new } == ["가나", " 다", "라"])
    }
}

/// 앱에서처럼 묶음을 직접 열지 않을 때: 런 루프 한 차례의 편집이 한 단계이고, 이어 친 글자는 한 단계로 합친다.
@MainActor
@Suite struct UndoEventGroupingTests {
    private func harness(_ text: String = "") throws -> EditorHarness {
        let h = try EditorHarness(text)
        h.editor.undoManager.groupsByEvent = true
        return h
    }

    /// 키 입력 하나(런 루프 한 차례).
    private func key(_ h: EditorHarness, _ text: String) async throws {
        h.view.insertText(text, replacementRange: h.view.selectedRange())
        try await Task.sleep(for: .milliseconds(2))
    }

    @Test func consecutiveTypingIsOneStepAndWordsAreSeparate() async throws {
        let h = try harness()
        for character in "가나 다라" { try await key(h, String(character)) }
        #expect(h.editor.text == "가나 다라")
        h.undo()
        #expect(h.editor.text == "가나")
        h.undo()
        #expect(h.editor.text.isEmpty)
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        h.redo()
        #expect(h.marked == "가나 다라|")
    }

    @Test func conversionIsItsOwnStepEvenWithinOneEvent() async throws {
        let h = try harness()
        for character in "**가**" { try await key(h, String(character)) }
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        h.undo()
        #expect(h.editor.text == "\\*\\*가\\*\\*")
        h.undo()
        #expect(h.editor.text == "**가*")
        h.undo()
        #expect(h.editor.text.isEmpty)
    }

    @Test func commandsInOneEventAreOneStepAndTheMenuReachesTheHistory() async throws {
        let h = try harness("- 하나")
        h.caret(atEndOfLine: 0)
        h.view.doCommand(by: NSResponder.newline)
        try await Task.sleep(for: .milliseconds(2))
        try await key(h, "둘")
        #expect(h.editor.text == "- 하나\n- 둘")
        // 편집 메뉴가 부르는 길(첫 응답자의 `undo:`).
        #expect(h.view.undoManager === h.editor.undoManager)
        h.view.undo(nil)
        #expect(h.editor.text == "- 하나\n- ")
        h.view.undo(nil)
        #expect(h.editor.text == "- 하나")
        h.view.redo(nil)
        #expect(h.editor.text == "- 하나\n- ")
    }

    @Test func compositionIsOneStep() async throws {
        let h = try harness("가")
        h.caret(at: 1)
        h.view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: h.view.selectedRange())
        try await Task.sleep(for: .milliseconds(2))
        h.view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: h.view.markedRange())
        try await Task.sleep(for: .milliseconds(2))
        h.view.insertText("한", replacementRange: h.view.markedRange())
        try await Task.sleep(for: .milliseconds(2))
        #expect(h.editor.text == "가한")
        h.undo()
        #expect(h.editor.text == "가")
        #expect(!h.editor.undoManager.canUndo)
    }
}
