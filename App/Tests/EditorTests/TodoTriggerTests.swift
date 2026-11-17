import AppKit
import Testing
@testable import Editor

/// `[ ]`, `[]`, `- [ ]` 뒤 Space가 어느 단계의 줄에서나 투두를 만든다(빈 줄, 글이 있는 줄, 글머리표 아래, 토글 안).
@MainActor
@Suite struct TodoTriggerTests {
    @Test(arguments: [
        ("|", ""), ("|본문", ""),
        ("- 부모\n\t|", "- 부모\n\t"), ("- 부모\n\t|본문", "- 부모\n\t"),
        ("+ 토글\n\t|", "+ 토글\n\t"), ("> 인용\n\t|", "> 인용\n\t"),
        ("- a\n\t- b\n\t\t|", "- a\n\t- b\n\t\t"),
    ])
    func bracketTriggersMakeATodo(start: String, head: String) throws {
        for typed in ["[ ] ", "[] "] {
            let h = try EditorHarness.at(start)
            h.type(typed)
            let index = h.document.lineIndex(at: h.editor.selectedRange.location)
            #expect(h.document.lines[index].kind == .todo(done: false), "\(start.debugDescription) + \(typed.debugDescription)")
            #expect(h.editor.text.hasPrefix(head + "[ ] "), "\(h.editor.text.debugDescription)")
        }
    }

    /// 글머리표 줄(Return으로 이어진 하위 항목)에서 친 `[ ]`와 `- [ ]`는 `- [ ] ` 꼴의 투두가 된다.
    @Test(arguments: ["[ ] ", "[] ", "- [ ] "])
    func onABulletLineTheStandardFormIsKept(typed: String) throws {
        let h = try EditorHarness.at("- 부모\n\t- |")
        h.type(typed)
        #expect(h.marked == "- 부모\n\t- [ ] |")
        #expect(h.document.lines[1].kind == .todo(done: false))
    }

    @Test func dashBracketOnAnEmptyLineMakesAStandardTodo() throws {
        let h = try EditorHarness()
        h.type("- [ ] 할 일")
        #expect(h.editor.text == "- [ ] 할 일")
        #expect(h.document.lines[0].kind == .todo(done: false))
    }

    @Test func onATodoLineTheSpaceIsTypedAsIs() throws {
        let h = try EditorHarness.at("[ ] |")
        h.type("[ ] ")
        #expect(h.marked == "[ ] [ ] |")
    }
}
