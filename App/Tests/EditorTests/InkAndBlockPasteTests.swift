import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct InkAndBlockPasteTests {
    @Test func paletteRoundTripsAndCodeStaysLiteral() {
        for color in InkColor.palette {
            let doc = MarkdownDocument("==가=={" + color.suffix + "} <u>**나**</u>" + color.comment)
            #expect(doc.lines[0].spans.map(\.kind) == [.highlight(color.id), .underline, .bold])
            #expect(doc.blockColor(at: 0) == color)
        }
        let literal = "==가=={민트} <!-- 없는 색 -->"
        #expect(CopyExport(source: literal).markdown == literal)
        let code = "```\n==가=={파랑} <u>나</u> <!-- 빨강 글자 -->\n```"
        #expect(CopyExport(source: code).markdown == code)
        #expect(MarkdownDocument("가 <!-- 빨강 글자 --> 나").blockColor(at: 0) == nil)
    }

    @Test func blockInkFollowsContinuationSplitJoinAndDuplicate() throws {
        let h = try EditorHarness.at("- 앞\\\n이|어짐\n\t- 하위")
        h.controller.selectBlocks()
        h.controller.setInk(InkColor(.green, foreground: true))
        defer { EditorController.lastInk = InkColor(.yellow) }
        #expect(h.editor.text == "- 앞\\\n이어짐 <!-- 초록 글자 -->\n\t- 하위")
        #expect(h.document.blockColor(at: 0) == h.document.blockColor(at: 1))
        #expect(h.document.blockColor(at: 2) == nil)
        h.perform(.duplicate)
        #expect(h.document.blockColor(at: 3) == InkColor(.green, foreground: true))
        h.perform(.highlight)
        #expect(h.document.blockColor(at: 3) == nil)
        let s = Scenario("앞|뒤 <!-- 노랑 바탕 -->")
        #expect(s.applying(EditorCommands.newline(s.doc, selection: s.selection)) == "앞 <!-- 노랑 바탕 -->\n|뒤")
        let joined = Scenario("앞 <!-- 노랑 바탕 -->\n|뒤 <!-- 빨강 글자 -->")
        #expect(joined.applying(EditorCommands.deleteBackward(joined.doc, selection: joined.selection).edit) == "앞|뒤 <!-- 노랑 바탕 -->")
        let across = Scenario("첫|째 <!-- 초록 글자 -->\n둘|째 <!-- 빨강 바탕 -->")
        #expect(across.applying(EditorCommands.replacing(across.doc, across.selection, with: "")) == "첫|째 <!-- 초록 글자 -->")
        let tail = Scenario("앞| <!-- 노랑 바탕 -->")
        #expect(tail.applying(EditorCommands.newline(tail.doc, selection: tail.selection)) == "앞 <!-- 노랑 바탕 -->\n|")
        let hidden = CaretSnapping.snap(old: tail.selection, new: NSRange(location: tail.doc.length, length: 0),
                                        in: tail.doc, folded: [], textChanged: true)
        #expect(hidden == tail.selection)
    }

    @Test func recoloringAcrossRunEdgeLeavesUnselectedTailInItsOriginalColor() throws {
        let s = Scenario("가|나==다|라=={3}")
        let edit = try #require(EditorCommands.setInk(s.doc, selection: s.selection, color: InkColor(.blue)))
        #expect(s.applying(edit) == "가==|나다|=={파랑}==라=={빨강}")
    }

    @Test func partialRecolorOnLaterLineReportsOnlyFinalFormatting() throws {
        let h = try EditorHarness.at("📝 앞줄\n가|나==다|라=={3}\n뒤")
        var reports: [Int] = []
        h.editor.onFormattingChange = { [weak h] in
            if let h { reports.append(h.controller.formattingState.highlight) }
        }
        let previous = EditorController.lastInk
        defer { EditorController.lastInk = previous }
        let blue = InkColor(.blue)
        h.step { h.controller.setInk(blue) }
        #expect(h.marked == "📝 앞줄\n가==|나다|=={파랑}==라=={빨강}\n뒤")
        #expect(reports == [blue.id])
        h.undo()
        #expect(h.marked == "📝 앞줄\n가|나==다|라=={3}\n뒤")
    }

    @Test func standardExportKeepsHierarchyAndHTMLStylesOnlyOwnBlock() {
        let red = InkColor(.red, foreground: true), blue = InkColor(.blue)
        let source = "+ 제목" + red.comment + "\n\t[x] <u>==글=={파랑}</u> **굵게** [링크](https://example.com)"
        let export = CopyExport(source: source)
        #expect(export.source == source)
        #expect(export.markdown == "- 제목\n\t- [x] 글 **굵게** [링크](https://example.com)")
        let html = export.html(highlightColors: [red.id: "#D44C47", blue.id: "#E7F3F8"])
        #expect(html.contains("<summary class=\"block-color-red\" style=\"color:#D44C47\">제목</summary><ul class=\"to-do-list\">"))
        #expect(html.contains("<u><mark class=\"highlight-blue_background\" style=\"background-color:#E7F3F8\">글</mark></u>"))
    }

    @Test func colorMenuAndShortcutsUseTheSameSelection() throws {
        let h = try EditorHarness.at(" |가| ")
        let menu = h.controller.inkMenu()
        let rows = menu.items.compactMap { $0.view as? NSStackView }
        #expect(rows.count == 2)
        let buttons = rows.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        #expect(buttons.count == 20)
        let red = try #require(buttons.first { $0.toolTip == "빨강 글자" })
        red.performClick(nil)
        defer { EditorController.lastInk = InkColor(.yellow) }
        #expect(h.editor.text == " ==가=={빨강 글자} ")
        h.perform(.highlight)
        #expect(h.editor.text == " 가 ")
        h.perform(.underline)
        #expect(h.editor.text == " <u>가</u> ")
        h.perform(.underline)
        #expect(h.editor.text == " 가 ")
    }

    @Test func doneForegroundAndBackgroundUseDoneFade() throws {
        let red = InkColor(.red, foreground: true), blue = InkColor(.blue)
        let h = try EditorHarness("[x] ==앞=={빨강 글자} <u>뒤</u>" + blue.comment)
        let display = try h.display(line: 0)
        let text = display.string as NSString
        let fg = display.attribute(.foregroundColor, at: text.range(of: "앞").location, effectiveRange: nil) as? NSColor
        #expect(fg == h.controller.style.ink(red, done: true))
        #expect(fg?.alphaComponent == h.controller.style.doneFade)
        #expect(h.controller.style.ink(blue, done: true).alphaComponent == h.controller.style.ink(blue).alphaComponent * h.controller.style.doneFade)
        #expect(display.attribute(.underlineStyle, at: text.range(of: "뒤").location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func siblingAndFirstChildPreserveFormatDepthSelectionAndUndo() throws {
        let source = "+ 부모\n\t- 기존\n다음"
        let clip = "\t[x] <u>하나</u> <!-- 노랑 바탕 -->\n\t\t- ==둘=={빨강 글자}\n\t- 셋"
        for inside in [false, true] {
            let h = try EditorHarness(source)
            h.editor.foldedLines = [0]
            h.controller.selectBlocks()
            h.controller.pasteSource(clip, inside: inside)
            let first = inside ? 1 : 2
            #expect(h.controller.blockSelection?.pastedRoots == [first, first + 2])
            #expect(h.document.lines[first].level == (inside ? 1 : 0))
            #expect(h.document.lines[first + 1].level == h.document.lines[first].level + 1)
            #expect(h.document.blockColor(at: first) == InkColor(.yellow))
            #expect(h.document.lines[first].kind == .todo(done: true))
            #expect(h.editor.foldedLines == (inside ? [] : [0]))
            h.undo()
            #expect(h.editor.text == source)
            #expect(h.editor.foldedLines == [0])
        }
    }

    @Test func caretAtParentEndAndLeafFallback() throws {
        let s = Scenario("+ 부모|\n\t기존")
        let plan = try #require(EditorCommands.pasteAtParentEnd(s.doc, text: "- 하나\n  - 둘", selection: s.selection, folded: []))
        #expect(plan.edit.applied(to: s.text) == "+ 부모\n\t- 하나\n\t\t- 둘\n\t기존")
        #expect(EditorCommands.pasteAtParentEnd(s.doc, text: "한 줄", selection: s.selection, folded: []) == nil)
        let nonParent = Scenario("\t- 본|문")
        #expect(EditorCommands.preparedForPaste(nonParent.doc, PasteSource("\t첫\n\t\t둘"), replacing: nonParent.selection).text == "첫\n\t\t둘")
        for source in ["---", "```\n코드\n```"] {
            let doc = MarkdownDocument(source)
            let plan = try #require(EditorCommands.blockPaste(doc, text: "- 다음", target: 0, belowRow: doc.lines.count - 1,
                                                              inside: true, folded: []))
            #expect(plan.edit.applied(to: source) == source + "\n- 다음")
        }
    }
}
