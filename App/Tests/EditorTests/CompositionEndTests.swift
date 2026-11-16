import AppKit
import Testing
@testable import Editor

/// 조합을 밖에서 끝낼 때(`unmarkText`, 포커스를 잃음, 조합 중의 ⌘Z, 조합 중인 글자에 겹친 바깥의 변경).
@MainActor
@Suite struct CompositionEndTests {
    @Test func unmarkKeepsThePairPutInForTheComposition() throws {
        let h = try EditorHarness.at("a |b")
        h.key(EditorShortcuts.Key.b, "b", .command)
        h.mark("ㅎ")
        #expect(h.editor.text == "a **ㅎ**b")
        h.view.unmarkText()
        #expect(h.editor.text == "a **ㅎ**b")
        #expect(h.changes.last == "a **ㅎ**b")
    }

    @Test func unmarkKeepsTheRunWhoseTextWasReplacedByTheComposition() throws {
        let h = try EditorHarness.at("a `|bc|` d")
        h.mark("ㅎ")
        h.view.unmarkText()
        #expect(h.editor.text == "a `ㅎ` d")
    }

    @Test func undoAndRedoInTheMiddleOfAComposition() throws {
        let h = try EditorHarness.at("a |b")
        h.key(EditorShortcuts.Key.b, "b", .command)
        h.mark("ㅎ")
        // 다시 할 것이 없을 때의 ⌘⇧Z는 조합만 끝내고 원문을 바꾸지 않는다.
        h.redo()
        #expect(h.editor.text == "a **ㅎ**b")
        h.undo()
        #expect(h.editor.text == "a b")
        h.redo()
        #expect(h.editor.text == "a **ㅎ**b")
    }

    @Test func losingFocusMidSyllableKeepsThePair() throws {
        let h = try EditorHarness.at("a |b")
        h.key(EditorShortcuts.Key.b, "b", .command)
        h.mark("ㅎ")
        #expect(h.window.makeFirstResponder(nil))
        #expect(!h.view.hasMarkedText())
        #expect(h.editor.text == "a **ㅎ**b")
        h.editor.controller.flushPendingChangeNow()
        #expect(h.changes.last == "a **ㅎ**b")
    }

    /// 조합이 정말 글자 없이 끝나면 넣어 둔 빈 쌍은 전처럼 지운다.
    @Test func compositionThatEndsEmptyStillRemovesThePair() throws {
        let h = try EditorHarness.at("a |b")
        h.key(EditorShortcuts.Key.b, "b", .command)
        h.mark("ㅎ")
        h.mark("")
        #expect(h.editor.text == "a b")
    }

    /// 조합 중인 글자에 겹친 바깥의 변경: 조합을 끝내며 옛 글을 알리지 않는다. 알리면 노트 창이 그 글을 저장해
    /// 방금 받은 변경을 덮어쓴다.
    @Test func outsideChangeOverTheComposingCharacterNeverReportsStaleText() throws {
        let h = try EditorHarness("가나")
        h.caret(at: 2)
        h.mark("ㅎ")
        #expect(h.changes.last == "가나ㅎ")
        let reported = h.changes.count
        h.editor.applyOutsideChange(to: "가나다라")
        #expect(h.editor.text == "가나다라")
        #expect(!h.view.hasMarkedText())
        h.editor.controller.flushPendingChangeNow()
        // 그 뒤에 알린 것이 있다면 모두 마지막 원문이다.
        #expect(h.changes.dropFirst(reported).allSatisfy { $0 == "가나다라" })
    }

    /// 알리지 않은 사용자의 변경이 있었으면 바깥의 변경까지 든 원문으로 한 번 알린다.
    @Test func pendingUserChangeIsReportedOnceWithTheFinalText() throws {
        let h = try EditorHarness("가나")
        h.caret(at: 2)
        h.mark("ㅎ")
        h.controller.hasPendingChange = true
        let reported = h.changes.count
        h.editor.applyOutsideChange(to: "가나다라")
        #expect(Array(h.changes.dropFirst(reported)) == ["가나다라"])
    }

    /// 닫는 기호를 쳐서 서식이 되는 입력은 원문을 두 번 고치지만 바깥에는 마지막 원문만 한 번 알린다.
    @Test func conversionReportsTheFinalTextOnce() throws {
        let h = try EditorHarness("")
        h.type("**가*")
        let reported = h.changes.count
        h.type("*")
        #expect(Array(h.changes.dropFirst(reported)) == ["**가**"])
        // 되돌리기는 전처럼 두 단계다.
        h.undo()
        #expect(h.editor.text == "\\*\\*가\\*\\*")
    }
}
