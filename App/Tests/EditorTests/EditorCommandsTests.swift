import Foundation
import Testing
@testable import Editor

/// 명령을 원문에 적용한 결과를 `|`(커서) 표기로 견준다. `|`가 둘이면 그 사이가 선택이다.
private struct Scenario {
    var text: String
    var selection: NSRange

    init(_ marked: String) {
        let parts = marked.components(separatedBy: "|")
        text = parts.joined()
        let start = parts[0].utf16.count
        selection = NSRange(location: start, length: parts.count > 2 ? parts[1].utf16.count : 0)
    }

    var doc: MarkdownDocument { MarkdownDocument(text) }

    func applying(_ edit: TextEdit?) -> String? {
        guard let edit else { return nil }
        let result = edit.applied(to: text) as NSString
        let end = result.replacingCharacters(in: NSRange(location: NSMaxRange(edit.selection), length: 0), with: "|") as NSString
        guard edit.selection.length > 0 else { return end as String }
        return end.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "|")
    }
}

@Suite struct IndentationTests {
    private func indent(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.indent(s.doc, selection: s.selection))
    }

    private func outdent(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.outdent(s.doc, selection: s.selection))
    }

    @Test func tabIndentsTheLineAndKeepsTheCaret() {
        #expect(indent("[ ] 할| 일") == "\t[ ] 할| 일")
        #expect(indent("- a\n- b|") == "- a\n\t- b|")
    }

    @Test func threeLevelsAndMore() {
        var text = "- 깊게|"
        for _ in 0..<3 { text = indent(text)! }
        #expect(text == "\t\t\t- 깊게|")
        #expect(MarkdownDocument("\t\t\t- 깊게").lines[0].level == 3)
    }

    @Test func stopsAtTheDeepestLevel() {
        let deepest = String(repeating: "\t", count: MarkdownDocument.maxLevel) + "- 끝|"
        #expect(indent(deepest) == nil)
    }

    @Test func indentsEverySelectedLine() {
        #expect(indent("- |a\n- b\n- c|\n- d") == "\t- |a\n\t- b\n\t- c|\n- d")
    }

    @Test func outdentRemovesOneTabOrTwoSpaces() {
        #expect(outdent("\t\t- a|") == "\t- a|")
        #expect(outdent("    - a|") == "  - a|")
        #expect(outdent("- a|") == nil)
        #expect(outdent("\t- |a\n\t\t- b|") == "- |a\n\t- b|")
    }

    @Test func tabInsideACodeBlockInsertsATab() {
        #expect(indent("```\nlet x|\n```") == "```\nlet x\t|\n```")
        #expect(outdent("```\n\tlet x|\n```") == "```\nlet x|\n```")
    }
}

@Suite struct NewlineTests {
    private func newline(_ marked: String, folded: Set<Int> = []) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.newline(s.doc, selection: s.selection, folded: folded))
    }

    @Test func continuesListsWithTheSameMarker() {
        #expect(newline("[ ] 하나|") == "[ ] 하나\n[ ] |")
        #expect(newline("[x] 끝낸 일|") == "[x] 끝낸 일\n[ ] |")
        #expect(newline("- [x] 표준|") == "- [x] 표준\n- [ ] |")
        #expect(newline("- 하나|") == "- 하나\n- |")
        #expect(newline("* 하나|") == "* 하나\n* |")
        #expect(newline("\t- 하위|") == "\t- 하위\n\t- |")
    }

    @Test func splitsInTheMiddle() {
        #expect(newline("[ ] 앞|뒤") == "[ ] 앞\n[ ] |뒤")
        #expect(newline("- 앞|가운데|뒤") == "- 앞\n- |뒤")
    }

    @Test func emptyItemEndsTheListOrOutdents() {
        #expect(newline("- 하나\n- |") == "- 하나\n|")
        #expect(newline("[ ] |") == "|")
        #expect(newline("\t- |") == "- |")
        #expect(newline("\t|") == "|")
    }

    @Test func headingAndParagraph() {
        #expect(newline("# 제목|") == "# 제목\n|")
        #expect(newline("본문|") == "본문\n|")
        #expect(newline("\t들여 쓴 본문|") == "\t들여 쓴 본문\n\t|")
    }

    @Test func toggleMakesAChildOrASiblingWhenFolded() {
        #expect(newline("> 토글|\n\t- 안") == "> 토글\n\t|\n\t- 안")
        #expect(newline("> 토글|\n\t- 안\n밖", folded: [0]) == "> 토글\n\t- 안\n> |\n밖")
    }

    @Test func fenceTriggerClosesTheBlock() {
        #expect(newline("```|") == "```\n|\n```")
        #expect(newline("```swift|") == "```swift\n|\n```")
        // 이미 닫힌 블록에서는 줄만 나눈다.
        #expect(newline("```|\ncode\n```") == "```\n|\ncode\n```")
    }

    @Test func codeKeepsItsIndentation() {
        #expect(newline("```\n    let x|\n```") == "```\n    let x\n    |\n```")
    }
}

@Suite struct InputTriggerTests {
    private func space(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.spaceTrigger(s.doc, selection: s.selection))
    }

    private func backspace(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.deleteBackward(s.doc, selection: s.selection))
    }

    @Test func bracketsThenSpaceBecomeATodo() {
        #expect(space("[]|") == "[ ] |")
        #expect(space("\t[]|") == "\t[ ] |")
        #expect(space("[]|남은 글") == "[ ] |남은 글")
        #expect(space("- []|") == "- [ ] |")
        #expect(MarkdownDocument("[ ] ").lines[0].kind == .todo(done: false))
    }

    @Test func otherTriggersNeedNoRewrite() {
        // `#`, `-`, `>` 뒤의 Space는 그대로 넣으면 그 문법이 된다.
        #expect(space("#|") == nil)
        #expect(space("-|") == nil)
        #expect(space(">|") == nil)
        #expect(space("글 []|") == nil)
        #expect(MarkdownDocument("# ").lines[0].kind == .heading(1))
        #expect(MarkdownDocument("## ").lines[0].kind == .heading(2))
        #expect(MarkdownDocument("### ").lines[0].kind == .heading(3))
        #expect(MarkdownDocument("- ").lines[0].kind == .bullet)
        #expect(MarkdownDocument("> ").lines[0].kind == .toggle)
    }

    @Test func backspaceAtContentStartRemovesTheMarker() {
        #expect(backspace("[ ] |할 일") == "|할 일")
        #expect(backspace("\t- |항목") == "\t|항목")
        #expect(backspace("> |토글") == "|토글")
        #expect(backspace("\t|들여 쓴 본문") == "|들여 쓴 본문")
    }

    @Test func backspaceElsewhereIsTheDefault() {
        #expect(backspace("[ ] 할| 일") == nil)
        #expect(backspace("|본문") == nil)
        #expect(backspace("# |제목") == nil)
    }
}

@Suite struct InlineCommandTests {
    private func wrap(_ marked: String, _ kind: EditorCommands.Wrap) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.toggleWrap(s.doc, selection: s.selection, kind))
    }

    private func highlight(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.cycleHighlight(s.doc, selection: s.selection))
    }

    private func link(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.link(s.doc, selection: s.selection))
    }

    @Test func wrapsAndUnwrapsTheSelection() {
        #expect(wrap("가 |굵게| 나", .bold) == "가 **|굵게|** 나")
        #expect(wrap("가 **|굵게|** 나", .bold) == "가 |굵게| 나")
        #expect(wrap("|취소|", .strike) == "~~|취소|~~")
        #expect(wrap("|코드|", .code) == "`|코드|`")
        #expect(wrap("`코|드`", .code) == "코|드")
    }

    @Test func emptySelectionInsertsAPair() {
        #expect(wrap("가|", .bold) == "가**|**")
    }

    @Test func doesNotWrapAcrossLinesOrInCode() {
        #expect(wrap("|가\n나|", .bold) == nil)
        #expect(wrap("```\n|코드|\n```", .bold) == nil)
    }

    @Test func highlightCyclesThroughFourColorsThenClears() {
        var text = "가 |형광| 나"
        var seen: [String] = []
        for _ in 0..<5 {
            text = highlight(text)!
            seen.append(text)
        }
        #expect(seen == [
            "가 ==|형광|== 나",
            "가 ==|형광|=={2} 나",
            "가 ==|형광|=={3} 나",
            "가 ==|형광|=={4} 나",
            "가 |형광| 나",
        ])
    }

    @Test func highlightCyclesWithTheCaretInside() {
        #expect(highlight("==형|광==") == "==형|광=={2}")
        #expect(highlight("==형광=={4}|") == "형광|")
    }

    @Test func linkPutsTheSelectionWhereItBelongs() {
        #expect(link("|문서|") == "[문서](|)")
        #expect(link("|https://a.example|") == "[|](https://a.example)")
        #expect(link("가|") == "가[|]()")
        #expect(link("[문|서](https://a.example)") == "문|서")
    }
}

@Suite struct BlockCommandTests {
    private func run(_ marked: String, _ command: (MarkdownDocument, NSRange) -> TextEdit?) -> String? {
        let s = Scenario(marked)
        return s.applying(command(s.doc, s.selection))
    }

    @Test func headingToggles() {
        #expect(run("제목|") { EditorCommands.toggleHeading($0, selection: $1, level: 1) } == "# 제목|")
        #expect(run("# 제목|") { EditorCommands.toggleHeading($0, selection: $1, level: 2) } == "## 제목|")
        #expect(run("## 제목|") { EditorCommands.toggleHeading($0, selection: $1, level: 2) } == "제목|")
        #expect(run("- 항목|") { EditorCommands.toggleHeading($0, selection: $1, level: 3) } == "### 항목|")
    }

    @Test func todoToggles() {
        #expect(run("할 일|") { EditorCommands.toggleTodo($0, selection: $1) } == "[ ] 할 일|")
        #expect(run("\t- 할 일|") { EditorCommands.toggleTodo($0, selection: $1) } == "\t[ ] 할 일|")
        #expect(run("[x] 할 일|") { EditorCommands.toggleTodo($0, selection: $1) } == "할 일|")
        #expect(run("|가\n[ ] 나|") { EditorCommands.toggleTodo($0, selection: $1) } == "[ ] |가\n[ ] 나|")
    }

    @Test func doneToggles() {
        #expect(run("[ ] 할| 일") { EditorCommands.toggleDone($0, selection: $1) } == "[x] 할| 일")
        #expect(run("[x] 할 일|") { EditorCommands.toggleDone($0, selection: $1) } == "[ ] 할 일|")
        // 빈 대괄호는 투두가 아니다(Space를 칠 때만 `[ ] `가 된다).
        #expect(run("[] 할 일|") { EditorCommands.toggleDone($0, selection: $1) } == nil)
        #expect(run("- [ ] 표준|") { EditorCommands.toggleDone($0, selection: $1) } == "- [x] 표준|")
        #expect(run("본문|") { EditorCommands.toggleDone($0, selection: $1) } == nil)
        // 하나라도 미완료면 모두 완료로.
        #expect(run("|[x] 가\n[ ] 나|") { EditorCommands.toggleDone($0, selection: $1) } == "|[x] 가\n[x] 나|")
    }

    @Test func doneKeepsACaretOnAnotherLine() {
        let doc = MarkdownDocument("[ ] 가\n본문")
        let edit = EditorCommands.toggleDone(doc, lines: 0...0, selection: NSRange(location: 8, length: 0))
        #expect(edit?.applied(to: doc.text) == "[x] 가\n본문")
        #expect(edit?.selection == NSRange(location: 8, length: 0))
    }

    @Test func codeBlockWrapsAndUnwraps() {
        #expect(run("|let x = 1|") { EditorCommands.toggleCodeBlock($0, selection: $1) } == "```\n|let x = 1|\n```")
        #expect(run("|") { EditorCommands.toggleCodeBlock($0, selection: $1) } == "```\n|\n```")
        #expect(run("```\nlet x| = 1\n```") { EditorCommands.toggleCodeBlock($0, selection: $1) } == "|let x = 1")
    }

    @Test func moveLinesUpAndDown() {
        func move(_ marked: String, _ direction: EditorCommands.MoveDirection, folded: Set<Int> = []) -> String? {
            let s = Scenario(marked)
            return s.applying(EditorCommands.moveLines(s.doc, selection: s.selection, folded: folded, direction: direction))
        }
        #expect(move("가\n나|\n다", .up) == "나|\n가\n다")
        #expect(move("가\n나|\n다", .down) == "가\n다\n나|")
        #expect(move("가|\n나", .up) == nil)
        #expect(move("가\n나|", .down) == nil)
        #expect(move("|가\n나|\n다", .down) == "다\n|가\n나|")
        // 접힌 토글은 감춘 줄과 함께 움직이고, 이웃이 접힌 토글이면 통째로 넘어간다.
        #expect(move("> 토글|\n\t- 안\n밖", .down, folded: [0]) == "밖\n> 토글|\n\t- 안")
        #expect(move("> 토글\n\t- 안\n밖|", .up, folded: [0]) == "밖|\n> 토글\n\t- 안")
    }

    @Test func moveLinesCarriesFoldState() {
        let doc = MarkdownDocument("> 토글\n\t- 안\n밖")
        let edit = EditorCommands.moveLines(doc, selection: NSRange(location: 0, length: 0), folded: [0], direction: .down)
        #expect(edit?.foldedAfter == [1])
    }
}

@Suite struct EditorShortcutsTests {
    @Test func matchesTheShortcutTable() {
        typealias Key = EditorShortcuts.Key
        let table: [(EditorShortcuts.Modifiers, UInt16, EditorAction)] = [
            ([.command, .shift], Key.nine, .toggleTodo),
            ([.command], Key.returnKey, .toggleDone),
            ([.command, .control], Key.up, .moveLineUp),
            ([.command, .control], Key.down, .moveLineDown),
            ([.command, .option], Key.leftBracket, .fold),
            ([.command, .option], Key.rightBracket, .unfold),
            ([.command, .option], Key.one, .heading(1)),
            ([.command, .option], Key.two, .heading(2)),
            ([.command, .option], Key.three, .heading(3)),
            ([.command], Key.b, .bold),
            ([.command, .shift], Key.x, .strikethrough),
            ([.command, .shift], Key.h, .highlight),
            ([.command], Key.e, .inlineCode),
            ([.command, .option], Key.c, .codeBlock),
            ([.command], Key.l, .link),
        ]
        for (modifiers, key, action) in table {
            #expect(EditorShortcuts.action(keyCode: key, modifiers: modifiers) == action)
        }
        // 노트 창과 시스템의 단축키는 가로채지 않는다.
        #expect(EditorShortcuts.action(keyCode: Key.c, modifiers: [.command]) == nil)
        #expect(EditorShortcuts.action(keyCode: Key.h, modifiers: [.command]) == nil)
        #expect(EditorShortcuts.action(keyCode: Key.b, modifiers: []) == nil)
    }
}
