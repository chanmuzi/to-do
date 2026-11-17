import AppKit
import Testing
@testable import Editor

/// 들여쓰기의 부모 규칙(D-043): 들여 쓴 줄은 바로 위 단계의 부모 항목(목록, 투두, 토글, 인용문) 아래에만 놓인다.
@Suite struct IndentRuleTests {
    private func indent(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.indent(s.doc, selection: s.selection))
    }

    @Test func plainParagraphsAndEmptyLinesWithoutAListParentDoNotIndent() {
        #expect(indent("본문|") == nil)
        #expect(indent("|") == nil)
        #expect(indent("본문\n|") == nil)
        #expect(indent("본문\n둘째|") == nil)
        #expect(indent("# 제목\n본문|") == nil)
        #expect(indent("```\n코드\n```\n본문|") == nil)
    }

    @Test(arguments: ["- 부모", "[ ] 부모", "- [x] 부모", "+ 토글", "> 인용"])
    func linesBelowAParentItemBecomeItsChild(parent: String) {
        #expect(indent(parent + "\n본문|") == parent + "\n\t본문|")
        #expect(indent(parent + "\n|") == parent + "\n\t|")
        #expect(indent(parent + "\n- 항목|") == parent + "\n\t- 항목|")
    }

    @Test func atMostOneLevelDeeperThanTheLineAbove() {
        #expect(indent("- a\n\t- b|") == nil)
        #expect(indent("- a\n\t- b\n- c|") == "- a\n\t- b\n\t- c|")
        #expect(indent("- a\n\t- b\n\t- c|") == "- a\n\t- b\n\t\t- c|")
        #expect(indent("- a\n\t본문\n\t- c|") == nil)
    }

    /// 바로 앞의 비지 않은 줄이 기준이다(빈 줄은 건너뛴다).
    @Test func emptyLinesBetweenAreSkipped() {
        #expect(indent("- a\n\n본문|") == "- a\n\n\t본문|")
        #expect(indent("본문\n\n- b|") == nil)
    }

    @Test func shiftTabIsUnchanged() {
        let s = Scenario("\t\t\t본문|")
        #expect(s.applying(EditorCommands.outdent(s.doc, selection: s.selection)) == "\t\t본문|")
    }

    // MARK: 안내선

    @Test func guidesOnlyForLevelsWithAParent() {
        let doc = MarkdownDocument("- a\n\t- b\n\t\t본문\n\t\t\t\t고아\n\t\t\n본문\n\t\t\t\t깊은 고아\n\t- c")
        #expect(ListStructure.guideLevels(in: doc) == [[], [0], [0, 1], [0, 1], [0, 1], [], [], []])
    }

    /// 다른 프로그램이 쓴 깊은 들여쓰기는 그대로 읽는다(원문을 고치지 않는다).
    @Test func orphanIndentsLoadUnchanged() {
        let text = "본문\n\t\t\t\t들여 쓴 본문\n\t- 항목"
        let doc = MarkdownDocument(text)
        #expect(doc.text == text)
        #expect(doc.lines.map(\.level) == [0, 4, 1])
        #expect(ListStructure.hasParent(in: doc) == [true, false, false])
    }
}

/// 부모를 지우거나 내어 쓰면 부모를 잃는 하위 줄이 함께 나온다(D-043). 실제 입력 경로로 확인한다.
@MainActor
@Suite struct OrphanAdoptionTests {
    @Test func outdentingAParentTakesItsChildren() throws {
        let h = try EditorHarness.at("- p\n\t- a|\n\t\t- b\n\t\t\t- c\n\t- d")
        h.press(NSResponder.backtab)
        #expect(h.marked == "- p\n- a|\n\t- b\n\t\t- c\n\t- d")
        // 한 단계로 되돌린다.
        h.undo()
        #expect(h.marked == "- p\n\t- a|\n\t\t- b\n\t\t\t- c\n\t- d")
    }

    @Test func backspaceThatTurnsTheParentIntoAParagraphOutdentsTheChildren() throws {
        let h = try EditorHarness.at("- |a\n\t- b\n\t\t본문\n끝")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|a\n- b\n\t본문\n끝")
    }

    @Test func deletingTheParentLineOutdentsTheChildren() throws {
        let h = try EditorHarness("머리\n- a\n\t- b\n\t- c")
        let line = h.document.lines[1]
        h.place(at: line.start, length: NSMaxRange(line.fullRange) - line.start)
        h.press(NSResponder.backspace)
        // `b`가 나오면 `c`는 `b`를 부모로 삼아 그대로 남는다(부모를 잃지 않는다).
        #expect(h.editor.text == "머리\n- b\n\t- c")
    }

    @Test func returnOnAnEmptyParentOutdentsTheChildrenWithIt() throws {
        let h = try EditorHarness.at("- p\n\t- |\n\t\t- b")
        h.press(NSResponder.newline)
        #expect(h.marked == "- p\n- |\n\t- b")
    }

    @Test func childrenThatKeepAParentStay() throws {
        let h = try EditorHarness.at("- p\n\t- a|\n\t- s")
        h.press(NSResponder.backtab)
        // `s`의 부모는 이제 `a`다(바로 위 단계의 가장 가까운 항목).
        #expect(h.marked == "- p\n- a|\n\t- s")
    }

    /// 부모 바로 위 단계의 가장 가까운 줄이 본문이면 부모가 아니다.
    @Test func aParagraphAboveIsNotAParent() throws {
        let h = try EditorHarness.at("- p\n- |a\n\t- b")
        h.press(NSResponder.backspace)
        #expect(h.marked == "- p\n|a\n- b")
    }

    /// 다른 프로그램이 쓴, 편집 전에도 부모가 없던 들여쓰기는 건드리지 않는다.
    @Test func existingOrphansAreLeftAlone() throws {
        let h = try EditorHarness.at("- |a\n\t- b\n본문\n\t\t\t고아")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|a\n- b\n본문\n\t\t\t고아")
    }

    /// 접힌 하위 토글은 감춘 줄과 함께 나오고 접힌 채로 남는다.
    @Test func aFoldedChildToggleMovesWithItsHiddenLinesAndStaysFolded() throws {
        let h = try EditorHarness("- p\n\t- a\n\t\t+ T\n\t\t\t안\n끝")
        h.editor.foldedLines = [2]
        h.caret(atEndOfLine: 1)
        h.press(NSResponder.backtab)
        #expect(h.editor.text == "- p\n- a\n\t+ T\n\t\t안\n끝")
        #expect(h.editor.foldedLines == [2])
        h.undo()
        #expect(h.editor.text == "- p\n\t- a\n\t\t+ T\n\t\t\t안\n끝")
        #expect(h.editor.foldedLines == [2])
    }

    @Test func tabOnAPlainLineDoesNothing() throws {
        let h = try EditorHarness.at("본문\n둘째|")
        h.press(NSResponder.tab)
        h.press(NSResponder.tab)
        #expect(h.marked == "본문\n둘째|")
        #expect(h.beeps == 0)
    }
}
