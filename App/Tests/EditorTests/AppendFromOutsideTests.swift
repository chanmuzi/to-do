import AppKit
import Testing
@testable import Editor

/// 바깥이 원문 끝에 덧붙인 글을 받을 때(`appendFromOutside`): 통째로 바꿔 넣는 것과 달리 커서, 접힘,
/// 되돌리기 기록, 조합 중인 글자를 그대로 둔다.
@MainActor
@Suite struct AppendFromOutsideTests {
    @Test func appendKeepsTheCaretAndIsNotReportedAsAUserEdit() async throws {
        let h = try EditorHarness("처음")
        h.caret(at: 2)

        h.editor.appendFromOutside("\n- [ ] 덧붙인 줄")
        // 미뤄 둔 알림이 있었다면 돌 차례를 준다.
        try await Task.sleep(for: .milliseconds(30))
        h.editor.flushPendingChange()

        #expect(h.editor.text == "처음\n- [ ] 덧붙인 줄")
        #expect(h.document.lines.count == 2)
        // 커서는 글 끝(붙인 글 앞)에 그대로 있다.
        #expect(h.editor.selectedRange == NSRange(location: 2, length: 0))
        #expect(h.changes.isEmpty)
        // 높이는 알린다(창이 따라 늘어야 한다).
        #expect(h.heights.last == h.editor.contentHeight)
        #expect(h.heights.count == 1)
    }

    /// 되돌리기 기록이 남고, ⌘Z는 붙인 글을 지우지 않고 사용자가 한 편집만 되돌린다.
    @Test func undoHistorySurvivesAndUndoLeavesTheAppendedTextAlone() throws {
        let h = try EditorHarness("처음")
        h.caret(at: 2)
        h.type("!")
        h.caret(at: 0)
        h.type("앞")
        #expect(h.editor.text == "앞처음!")

        h.editor.appendFromOutside("\n덧붙인 줄")

        #expect(h.editor.undoManager.canUndo)
        h.undo()
        #expect(h.editor.text == "처음!\n덧붙인 줄")
        h.undo()
        #expect(h.editor.text == "처음\n덧붙인 줄")
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        h.redo()
        h.editor.flushPendingChange()
        #expect(h.editor.text == "앞처음!\n덧붙인 줄")
        // 되돌린 글은 사용자의 편집으로 알린다(붙인 글까지 든 원문).
        #expect(h.changes.last == "앞처음!\n덧붙인 줄")
    }

    @Test func foldsStayOnTheirLines() throws {
        let h = try EditorHarness("> 토글\n\t안쪽\n끝")
        h.caret(at: 1)
        h.perform(.fold)
        #expect(h.editor.foldedLines == [0])
        let reported = h.foldChanges.count

        h.editor.appendFromOutside("\n> 덧붙인 토글\n\t안")

        #expect(h.editor.foldedLines == [0])
        #expect(h.foldChanges.count == reported)
        #expect(h.editor.text == "> 토글\n\t안쪽\n끝\n> 덧붙인 토글\n\t안")
    }

    /// 한글을 조합하는 중에 덧붙여도 조합이 끊기지 않는다. 입력기를 거치지 않고 저장소가 바뀌면 텍스트 뷰가
    /// 조합을 끝내므로, 화면에 넣는 일은 조합이 끝날 때까지 미루고 원문에는 곧바로 넣는다.
    @Test func compositionAtTheEndIsKeptAndTheAppendedTextIsNeverMissingFromTheSource() throws {
        let h = try EditorHarness("처음")
        h.caret(at: 2)
        h.mark("ㅎ")
        #expect(h.view.hasMarkedText())
        let marked = h.view.markedRange()
        #expect(h.changes.last == "처음ㅎ")

        h.editor.appendFromOutside("\n덧붙인 줄")

        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == marked)
        // 원문에는 이미 들어 있다(저장되는 글에서 빠지지 않는다).
        #expect(h.editor.text == "처음ㅎ\n덧붙인 줄")
        #expect(h.view.string == "처음ㅎ")

        // 조합이 이어지는 동안 알리는 글에도 들어 있다.
        h.mark("하")
        #expect(h.view.hasMarkedText())
        #expect(h.changes.last == "처음하\n덧붙인 줄")

        // 조합을 확정하면 화면에도 들어가고, 커서는 친 글자 뒤에 있다.
        h.commit("한")
        #expect(!h.view.hasMarkedText())
        #expect(h.view.string == "처음한\n덧붙인 줄")
        #expect(h.editor.text == "처음한\n덧붙인 줄")
        #expect(h.changes.last == "처음한\n덧붙인 줄")
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 0))
        #expect(h.editor.undoManager.canUndo)
    }

    /// 글 가운데에서 조합하는 중이어도 같다(원문 저장소가 바뀌면 자리와 상관없이 조합이 끝난다).
    @Test func compositionAwayFromTheEndIsKeptToo() throws {
        let h = try EditorHarness("처음\n끝")
        h.caret(at: 2)
        h.mark("ㅎ")
        let marked = h.view.markedRange()

        h.editor.appendFromOutside("\n덧붙인 줄")

        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == marked)
        #expect(h.view.string == "처음ㅎ\n끝")
        #expect(h.editor.text == "처음ㅎ\n끝\n덧붙인 줄")
        h.commit("한")
        #expect(h.view.string == "처음한\n끝\n덧붙인 줄")
        #expect(h.editor.text == "처음한\n끝\n덧붙인 줄")
        #expect(h.changes.last == "처음한\n끝\n덧붙인 줄")
    }

    /// 조합을 미뤄 둔 채 바깥에서 글을 통째로 넣으면 미뤄 둔 덧붙임은 버린다(새 글이 기준이다).
    @Test func assigningTextDropsADeferredAppend() throws {
        let h = try EditorHarness("처음")
        h.caret(at: 2)
        h.mark("ㅎ")
        h.editor.appendFromOutside("\n덧붙인 줄")

        h.editor.text = "밖에서 통째로 넣은 글"

        #expect(h.editor.text == "밖에서 통째로 넣은 글")
        #expect(h.view.string == "밖에서 통째로 넣은 글")
    }

    /// 아직 알리지 않은 사용자의 변경이 있었다면 버리지 않는다. 다음에 알릴 때 붙인 글까지 나간다.
    @Test func aPendingUserChangeIsStillReportedWithTheAppendedText() throws {
        let h = try EditorHarness("처음")
        // 텍스트 뷰를 거치지 않은 변경: 편집기는 다음 메인 큐 차례에 알리려고 표시해 둔다.
        let storage = try #require(h.view.textStorage)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "아직 알리지 않은 글 ")
        #expect(h.changes.isEmpty)

        h.editor.appendFromOutside("\n덧붙인 줄")
        #expect(h.changes.isEmpty)
        h.editor.flushPendingChange()

        #expect(h.changes == ["아직 알리지 않은 글 처음\n덧붙인 줄"])
    }

    @Test func lineEndingsAreNormalisedAndEmptyAppendDoesNothing() throws {
        let h = try EditorHarness("처음")
        h.caret(at: 2)
        h.type("!")
        h.editor.appendFromOutside("")
        h.editor.appendFromOutside("\r\n둘\r셋")

        #expect(h.editor.text == "처음!\n둘\n셋")
        #expect(h.editor.undoManager.canUndo)
    }
}
