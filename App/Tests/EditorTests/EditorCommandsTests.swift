import AppKit
import Testing
@testable import Editor

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
        #expect(indent("[ ] 위\n[ ] 할| 일") == "[ ] 위\n\t[ ] 할| 일")
        #expect(indent("- a\n- b|") == "- a\n\t- b|")
    }

    @Test func threeLevelsAndMore() {
        var text = "- 1\n\t- 2\n\t\t- 3\n- 깊게|"
        for _ in 0..<3 { text = indent(text)! }
        #expect(text == "- 1\n\t- 2\n\t\t- 3\n\t\t\t- 깊게|")
        #expect(MarkdownDocument("\t\t\t- 깊게").lines[0].level == 3)
    }

    @Test func stopsAtTheDeepestLevel() {
        let deepest = String(repeating: "\t", count: MarkdownDocument.maxLevel)
        #expect(indent(deepest + "- 부모\n" + deepest + "- 끝|") == nil)
    }

    /// 묶음 밖에 부모가 있어야 고른 줄 모두 함께 들어간다.
    @Test func indentsEverySelectedLine() {
        #expect(indent("- |a\n- b\n- c|\n- d") == nil)
        #expect(indent("- p\n- |a\n- b\n- c|\n- d") == "- p\n\t- |a\n\t- b\n\t- c|\n- d")
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

    @MainActor @Test(arguments: [
        ("+ |회의 준비", "+ \n+ |회의 준비", false),
        ("+ |프로젝트 A\n\t일정 정리\n다음 문단", "+ \n+ |프로젝트 A\n\t일정 정리\n다음 문단", true),
        ("## |이번 주\n월요일까지 초안", "\n## |이번 주\n월요일까지 초안", false),
        ("[x] |보고서 제출\n[ ] 회의록 공유", "[ ] \n[x] |보고서 제출\n[ ] 회의록 공유", false),
        ("- |마감 이번 주 금요일 <!-- 노랑 바탕 -->\n- 자료 모으기", "- \n- |마감 이번 주 금요일 <!-- 노랑 바탕 -->\n- 자료 모으기", false),
        ("+ 회의 준비|", "+ 회의 준비\n\t|", false),
        ("+ 회의 준비|", "+ 회의 준비\n+ |", true),
        ("+ 프로젝트 A|\n\t- 일정 정리\n다음 문단", "+ 프로젝트 A\n\t|\n\t- 일정 정리\n다음 문단", false),
        ("+ 프로젝트 |회고\n\t일정 정리\n다음 문단", "+ 프로젝트\n\t일정 정리\n+ |회고\n다음 문단", true),
        ("- 장보기|\n\t- 우유\n\t- 계란\n- 세탁소", "- 장보기\n- |\n\t- 우유\n\t- 계란\n- 세탁소", false),
        ("> 작은 일부터 끝낸다.|", "> 작은 일부터 끝낸다.\n|", false),
        ("\t+ ## 앞|뒤", "\t+ ## 앞\n\t\t|뒤", false),
        ("\t> 앞|뒤", "\t> 앞\n\t|뒤", false),
        ("- 위\\\n|계속", "- 위\\\n\n- |계속", false),
    ])
    func returnPolicy(_ before: String, _ after: String, _ folded: Bool) throws {
        let h = try EditorHarness.at(before)
        h.editor.load(text: h.editor.text, foldedLines: folded ? [0] : [], openedEmptyToggleLines: folded ? [] : [0])
        h.press(NSResponder.newline)
        #expect(h.marked == after)
        if folded {
            let sibling = before.hasPrefix("+ |") ? 0 : h.document.lineIndex(at: h.editor.selectedRange.location)
            #expect(h.editor.foldedLines == [sibling, before.hasPrefix("+ |") ? 1 : 0])
        }
        h.undo()
        #expect(h.marked == before)
        if folded { #expect(h.editor.foldedLines == [0]) }
    }

    @MainActor @Test func foldedMultilineHeadingSplitsAfterItsLastContinuation() throws {
        let h = try EditorHarness.at("+ # 앞\\\n중|간 <!-- 노랑 바탕 -->\n\t+ 하위\n\t\t안\n끝")
        h.editor.foldedLines = [0, 2]
        h.press(NSResponder.newline)
        #expect(h.marked == "+ # 앞\\\n중 <!-- 노랑 바탕 -->\n\t+ 하위\n\t\t안\n+ # |간\n끝")
        #expect(h.editor.foldedLines == [0, 2, 4])
        h.undo()
        #expect(h.marked == "+ # 앞\\\n중|간 <!-- 노랑 바탕 -->\n\t+ 하위\n\t\t안\n끝")
        #expect(h.editor.foldedLines == [0, 2])
    }

    @Test func firstEmptyPhysicalLineOfANonemptyBlockKeepsItsContinuation() {
        #expect(newline("+ |\\\n회의") == "+ \n+ |\\\n회의")
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

    @Test func emptyItemKeepsItsDepth() {
        #expect(newline("- 하나\n- |") == "- 하나\n|")
        #expect(newline("[ ] |") == "|")
        #expect(newline("\t- |") == "\t|")
        #expect(newline("\t|") == "|")
    }

    @Test func headingAndParagraph() {
        #expect(newline("# 제목|") == "# 제목\n|")
        #expect(newline("본문|") == "본문\n|")
        #expect(newline("\t들여 쓴 본문|") == "\t들여 쓴 본문\n\t|")
    }

    @Test func toggleMakesAChildOrASiblingWhenFolded() {
        #expect(newline("+ 토글|\n\t- 안") == "+ 토글\n\t|\n\t- 안")
        #expect(newline("+ 토글|\n\t- 안\n밖", folded: [0]) == "+ 토글\n\t- 안\n+ |\n밖")
    }

    @Test func returnInsideAFormattedRunSplitsTheRun() {
        // 구간은 줄을 넘지 못한다. 줄바꿈 앞에서 닫고 다음 줄에서 다시 연다.
        #expect(newline("**굵|게**") == "**굵**\n**|게**")
        #expect(newline("- ==형|광=={3}") == "- ==형=={빨강}\n- ==|광=={3}")
        #expect(newline("[글|자](https://a.example)") == "[글](https://a.example)\n[|자](https://a.example)")
        #expect(newline("**~~가|나~~**") == "**~~가~~**\n**~~|나~~**")
        // 구간의 끝이나 앞에서는 나눌 것이 없다. 빈 구간을 남기지 않는다.
        #expect(newline("**굵게|**") == "**굵게**\n|")
        #expect(newline("**|굵게**") == "\n**|굵게**")
        // 커서 뒤의 공백은 줄바꿈과 함께 지운다(새 줄의 맨 앞에서 감춘 들여쓰기가 되지 않게).
        #expect(newline("가 **굵게**| 나") == "가 **굵게**\n|나")
    }

    @Test func returnOnTheEmptyLastLineLeavesTheCodeBlock() {
        // 빈 마지막 줄을 지우고 블록 아래에 새 문단을 연다.
        #expect(newline("```\ncode\n|\n```") == "```\ncode\n```\n|")
        #expect(newline("```swift\ncode\n|\n```\n뒤") == "```swift\ncode\n```\n|\n뒤")
        #expect(newline("\t```\n\tcode\n\t|\n\t```") == "\t```\n\tcode\n\t```\n\t|")
        // 닫히지 않은 블록(문서 끝까지 이어진다)은 닫는 줄을 넣는다.
        #expect(newline("```\ncode\n|") == "```\ncode\n```\n|")
        // 줄이 하나뿐인 블록, 빈 줄이 마지막이 아닌 경우, 글이 있는 줄에서는 줄만 나눈다.
        #expect(newline("```\n|\n```") == "```\n\n|\n```")
        #expect(newline("```\n|\ncode\n```") == "```\n\n|\ncode\n```")
        #expect(newline("```\ncode|\n```") == "```\ncode\n|\n```")
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

    private func backtick(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.codeBlockTrigger(s.doc, selection: s.selection))
    }

    private func backspace(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.deleteBackward(s.doc, selection: s.selection).edit)
    }

    @Test func bracketsThenSpaceBecomeATodo() {
        #expect(space("[]|") == "[ ] |")
        #expect(space("\t[]|") == "\t[ ] |")
        #expect(space("[]|남은 글") == "[ ] |남은 글")
        #expect(space("- []|") == "- [ ] |")
        #expect(MarkdownDocument("[ ] ").lines[0].kind == .todo(done: false))
    }

    @Test func everyTriggerOnAnEmptyLine() {
        #expect(space("#|") == "# |")
        #expect(space("##|") == "## |")
        #expect(space("###|") == "### |")
        #expect(space("-|") == "- |")
        #expect(space("*|") == "- |")
        #expect(space(">|") == "+ |")
        #expect(space("[]|") == "[ ] |")
        #expect(MarkdownDocument("# ").lines[0].kind == .heading(1))
        #expect(MarkdownDocument("## ").lines[0].kind == .heading(2))
        #expect(MarkdownDocument("### ").lines[0].kind == .heading(3))
        #expect(MarkdownDocument("- ").lines[0].kind == .bullet)
        #expect(MarkdownDocument("+ ").lines[0].kind == .toggle)
    }

    @Test func triggersOnALineThatAlreadyHasText() {
        #expect(space("#|글") == "# |글")
        #expect(space("##|글 더") == "## |글 더")
        #expect(space("-|글") == "- |글")
        #expect(space(">|글") == "+ |글")
        #expect(space("[]|글") == "[ ] |글")
    }

    @Test func triggersConvertBetweenBlockTypes() {
        // 줄 머리 기호는 보이지 않으므로 기호는 글자가 보이기 시작하는 자리에 친다.
        #expect(space("# -|제목") == "- |제목")
        #expect(space("- ##|항목") == "## |항목")
        #expect(space("### #|제목") == "# |제목")
        #expect(space("[x] >|끝낸 일") == "+ |끝낸 일")
        #expect(space("+ []|토글") == "[ ] |토글")
        #expect(space("- [ ] -|표준 투두") == "- |표준 투두")
        #expect(space("+ ###|토글") == "+ ### |토글")
        // 들여쓰기는 그대로다.
        #expect(space("\t- #|항목") == "\t# |항목")
        #expect(space("\t\t[ ] -|할 일") == "\t\t- |할 일")
    }

    @Test func triggerAfterAHiddenInlineMarkerStillCounts() {
        // 줄이 서식 구간으로 시작하면 커서는 여는 기호 뒤에 있다. 친 기호는 구간 안에 들어가 있다.
        #expect(space("**-|굵게** 뒤") == "- **|굵게** 뒤")
        #expect(space("# ==##|형광==") == "## ==|형광==")
    }

    @Test func noTriggerAwayFromTheVisualStartOrForTheSameType() {
        #expect(space("글 []|") == nil)
        #expect(space("글 #|") == nil)
        #expect(space("####|") == nil)
        #expect(space("--|") == nil)
        // 이미 그 종류인 줄에서는 공백을 그대로 넣는다.
        #expect(space("- -|항목") == nil)
        #expect(space("# #|제목") == nil)
        #expect(space("[ ] []|할 일") == nil)
        #expect(space("```\n#|\n```") == nil)
    }

    @Test func thirdBacktickMakesACodeBlock() {
        #expect(backtick("``|") == "```\n|\n```")
        #expect(backtick("``|let x = 1") == "```\n|let x = 1\n```")
        #expect(backtick("앞\n``|\n뒤") == "앞\n```\n|\n```\n뒤")
        // 다른 종류의 줄에서는 줄 머리를 떼고, 들여쓰기는 그대로 둔다.
        #expect(backtick("- ``|항목") == "```\n|항목\n```")
        #expect(backtick("\t# ``|제목") == "\t```\n\t|제목\n\t```")
        // 줄 맨 앞이 아니면 바꾸지 않는다.
        #expect(backtick("글 ``|") == nil)
        #expect(backtick("`|") == nil)
    }

    /// 코드 블록 안에서 빈 줄에 친 백틱 셋은 블록에서 나가게 한다(새 ``` 줄이 생기지 않는다).
    @Test func thirdBacktickInsideACodeBlockLeavesTheBlock() {
        // 마지막 줄: Return과 같다.
        #expect(backtick("```\ncode\n``|\n```\nafter **b**") == "```\ncode\n```\n|\nafter **b**")
        // 첫 줄: 블록 위에 문단을 연다. 가운데 줄: 블록을 둘로 나눈다.
        #expect(backtick("```\n``|\ncode\n```") == "|\n```\ncode\n```")
        #expect(backtick("```\na\n``|\nb\n```") == "```\na\n```\n|\n```\nb\n```")
        // 줄이 하나뿐인 블록은 블록을 없앤다.
        #expect(backtick("```\n``|\n```") == "|")
        // 닫히지 않은 블록은 닫는다.
        #expect(backtick("```\ncode\n``|") == "```\ncode\n```\n|")
        // 글이 있는 줄, 줄 가운데에서는 백틱이 글자로 들어간다.
        #expect(backtick("```\nx``|\n```") == nil)
        #expect(backtick("```\n``|x\n```") == nil)
    }

    @Test func backspaceAtContentStartRemovesTheMarker() {
        #expect(backspace("[ ] |할 일") == "|할 일")
        #expect(backspace("\t- |항목") == "\t|항목")
        #expect(backspace("+ |토글") == "|토글")
        #expect(backspace("\t|들여 쓴 본문") == "|들여 쓴 본문")
        // 제목도 본문으로 돌아간다(`#`이 보이지 않으므로 글자로 지울 수 없다).
        #expect(backspace("# |제목") == "|제목")
        #expect(backspace("\t### |제목") == "\t|제목")
        // 줄이 서식 구간으로 시작해 커서가 감춘 여는 기호 뒤에 있어도 같다.
        #expect(backspace("- **|굵게**") == "**|굵게**")
    }

    @Test func backspaceElsewhereIsTheDefault() {
        #expect(EditorCommands.deleteBackward(MarkdownDocument("[ ] 할 일"), selection: NSRange(location: 5, length: 0)) == .passThrough)
        #expect(EditorCommands.deleteBackward(MarkdownDocument("본문"), selection: NSRange(location: 0, length: 0)) == .passThrough)
        #expect(EditorCommands.deleteBackward(MarkdownDocument("앞\n본문"), selection: NSRange(location: 2, length: 0)) == .passThrough)
        #expect(EditorCommands.deleteBackward(MarkdownDocument("본문"), selection: NSRange(location: 0, length: 1)) == .passThrough)
    }
}

@Suite struct InlineCommandTests {
    private func wrap(_ marked: String, _ kind: EditorCommands.Wrap) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.toggleWrap(s.doc, selection: s.selection, kind))
    }

    private func highlight(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.setInk(s.doc, selection: s.selection, color: InkColor(.yellow), toggle: true))
    }

    @Test func wrapsAndUnwrapsTheSelection() {
        #expect(wrap("가 |굵게| 나", .bold) == "가 **|굵게|** 나")
        #expect(wrap("가 **|굵게|** 나", .bold) == "가 |굵게| 나")
        #expect(wrap("|취소|", .strike) == "~~|취소|~~")
        #expect(wrap("|코드|", .code) == "`|코드|`")
        #expect(wrap("`|코드|`", .code) == "|코드|")
        // 기호까지 고른 선택도 보이는 글자로 맞춰 본다.
        #expect(wrap("가 |**굵게**| 나", .bold) == "가 |굵게| 나")
    }

    @Test func aCaretIsNotAnEditOfTheSource() {
        // 선택이 없으면 원문을 고치지 않는다(다음에 칠 글자의 서식만 정한다. `TypingMarksTests`).
        #expect(wrap("가|", .bold) == nil)
        #expect(highlight("==형|광==") == nil)
    }

    @Test func unwrappingPartOfARunKeepsTheRestFormatted() {
        #expect(wrap("**가|나|다**", .bold) == "**가**|나|**다**")
        #expect(wrap("**|가|나다**", .bold) == "|가|**나다**")
        #expect(wrap("**가나|다|**", .bold) == "**가나**|다|")
        #expect(wrap("`가|나|다`", .code) == "`가`|나|`다`")
        // 안쪽의 다른 구간과 엇갈리면 그 구간까지 넣는다.
        // 남는 조각의 끝 공백은 기호 밖에 둔다(닫는 기호 바로 앞은 공백일 수 없다).
        #expect(wrap("**가 ~~나|다~~ 라|**", .bold) == "**가** |~~나다~~ 라|")
    }

    @Test func wrappingMergesRunsOfTheSameKind() {
        #expect(wrap("가|나**다|라**", .bold) == "가**|나다라|**")
        #expect(wrap("|**가** 나 **다**|", .bold) == "**|가 나 다|**")
        // 다른 서식에 걸친 선택은 그 구간을 통째로 감싼다(기호가 엇갈리지 않게).
        #expect(wrap("가|나~~다|라~~", .bold) == "가**|나~~다라~~|**")
        // 다른 서식 구간 안에서는 그 안에 겹쳐 넣는다.
        #expect(wrap("~~|가나|~~", .bold) == "~~**|가나|**~~")
        #expect(wrap("~~가|나|다~~", .bold) == "~~가**|나|**다~~")
    }

    @Test func codeSpansTakeNoOtherFormatInside() {
        #expect(wrap("`가|나|다`", .bold) == nil)
        // 코드의 글자를 모두 골랐으면 코드 구간 바깥에서 감싼다.
        #expect(wrap("앞 `|코드|` 뒤", .bold) == "앞 **|`코드`|** 뒤")
        // 코드로 감싸면 안의 기호가 글자로 드러나므로 벗긴다. 링크는 감싸지 않는다.
        #expect(wrap("|가 **나** 다|", .code) == "`|가 나 다|`")
        #expect(wrap("|가 [나](https://a.example)|", .code) == nil)
    }

    @Test func doesNotWrapAcrossLinesOrInCode() {
        #expect(wrap("|가\n나|", .bold) == nil)
        #expect(wrap("```\n|코드|\n```", .bold) == nil)
    }

    @Test func applyingLastColorTwiceClearsIt() {
        #expect(highlight("가 |형광| 나") == "가 ==|형광|=={노랑} 나")
        #expect(highlight("가 ==|형광|=={노랑} 나") == "가 |형광| 나")
    }

    @Test func highlightChangesOnlyTheSelectedPart() {
        #expect(highlight("==가|나|다==") == "==가=={노랑}|나|==다=={노랑}")
        #expect(highlight("==가|나|다=={4}") == "==가=={파랑}==|나|=={노랑}==다=={파랑}")
        #expect(highlight("가|나==다|라=={3}") == "가==|나다|=={노랑}==라=={빨강}")
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
        #expect(move("+ 토글|\n\t- 안\n밖", .down, folded: [0]) == "밖\n+ 토글|\n\t- 안")
        #expect(move("+ 토글\n\t- 안\n밖|", .up, folded: [0]) == "밖|\n+ 토글\n\t- 안")
    }

    @Test func moveLinesCarriesFoldState() {
        let doc = MarkdownDocument("+ 토글\n\t- 안\n밖")
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
            ([.command, .option], Key.v, .pasteInside),
            ([.command], Key.u, .underline),
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
