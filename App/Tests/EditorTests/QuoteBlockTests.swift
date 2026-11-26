import AppKit
import Testing
import Theme
@testable import Editor

/// 인용문(`> `)과, 그와 겹치지 않게 바꾼 토글의 원문 표기(`+ `). D-044.
@MainActor
@Suite struct QuoteBlockTests {
    @Test func sourceNotationReadsQuotesAndToggles() {
        let doc = MarkdownDocument("> 인용\n+ 토글\n\t> 안쪽 인용\n>붙여 쓰면 본문")
        #expect(doc.lines.map(\.kind) == [.quote, .toggle, .quote, .paragraph])
        #expect(doc.lines.map(\.markerLength) == [2, 2, 2, 0])
    }

    /// 줄 맨 앞의 `"`나 `|` 뒤 Space가 인용문을 만든다. 원문은 표준 Markdown의 `> `다.
    @Test(arguments: ["\"", "|"])
    func quoteTriggerConvertsTheLine(trigger: String) throws {
        let h = try EditorHarness()
        h.type(trigger + " 말")
        #expect(h.editor.text == "> 말")
        #expect(h.document.lines[0].kind == .quote)
        // 되돌리면 친 기호가 보통 글자로 남는다.
        h.undo()
        #expect(h.editor.text == "> ")
        h.undo()
        #expect(h.editor.text == trigger)
    }

    @Test func quoteTriggerWorksOnALineWithTextAndIndented() throws {
        let h = try EditorHarness.at("- 부모\n\t|본문")
        h.type("\" ")
        #expect(h.marked == "- 부모\n\t> |본문")
    }

    /// 토글은 여전히 `>` 뒤 Space로 치고, 원문에는 `+ `로 적는다.
    @Test func toggleTriggerWritesThePlusMarker() throws {
        let h = try EditorHarness()
        h.type("> 토글")
        #expect(h.editor.text == "+ 토글")
        #expect(h.document.lines[0].kind == .toggle)
    }

    @Test func returnLeavesTheQuote() throws {
        let h = try EditorHarness.at("> 첫 줄|")
        h.press(NSResponder.newline)
        #expect(h.marked == "> 첫 줄\n|")
        h.type("둘째")
        h.press(NSResponder.newline)
        h.press(NSResponder.newline)
        #expect(h.marked == "> 첫 줄\n둘째\n\n|")
    }

    @Test func returnOnAnEmptyNestedQuoteOutdents() throws {
        let h = try EditorHarness.at("- 부모\n\t> |")
        h.press(NSResponder.newline)
        #expect(h.marked == "- 부모\n> |")
    }

    @Test func backspaceAtTheStartLeavesTheQuote() throws {
        let h = try EditorHarness.at("앞\n> |인용")
        h.press(NSResponder.backspace)
        #expect(h.marked == "앞\n|인용")
        h.press(NSResponder.backspace)
        #expect(h.marked == "앞|인용")
    }

    @Test func quoteLinesUseTheBodyTextColorAndABar() throws {
        let h = try EditorHarness("> 인용 **굵게**\n> 둘째\n본문")
        let decoration = try #require(try h.display(line: 0).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(decoration.quoteBar)
        #expect(decoration.gutter == nil)
        #expect(try h.color(line: 0, at: h.document.lines[0].contentStart) == h.controller.style.text)
        let style = try #require(try h.display(line: 0).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent == h.controller.style.gutter)
        // 인라인 서식은 그대로 입힌다.
        let bold = h.document.lines[0].spans[0].contentRange
        let font = try h.display(line: 0).attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont
        #expect(font == h.controller.style.strong)
        let plain = try #require(try h.display(line: 2).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(!plain.quoteBar)
    }

    @Test(arguments: [CheckboxStyle.box, .bracket])
    func continuedQuoteUsesOneBarAndTheListGutter(_ checkbox: CheckboxStyle) throws {
        let h = try EditorHarness("- 부모\n\t> 첫 줄\\\n\t둘째\n\t> 셋째\n\t- 목록", checkbox: checkbox)
        for row in 1...3 {
            let paragraph = try h.display(line: row)
            let decoration = try #require(paragraph.attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
            #expect(decoration.quoteBar)
            #expect(decoration.startsQuote == (row == 1))
            #expect(decoration.endsQuote == (row == 3))
            #expect(decoration.gutterX == h.controller.style.indent)
            let style = try #require(paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.headIndent == h.controller.style.indent + h.controller.style.gutter)
        }
        #expect(h.controller.style.quoteBarWidth == 3)
        #expect(h.controller.style.quoteBarInset == 4)
    }

    @Test func trailingEmptyContinuationFinishesTheBar() throws {
        let h = try EditorHarness.at("> 인용|")
        h.press(#selector(NSResponder.insertLineBreak(_:)))
        let first = try h.display(line: 0)
        let decoration = try #require(first.attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(decoration.coversTrailingQuote && decoration.startsQuote && decoration.endsQuote)
    }

    @Test func copyExportsQuotesAsStandardMarkdownAndBlockquote() {
        let doc = MarkdownDocument("> 첫 **줄**\n> 둘째\n본문\n+ 토글\n\t안")
        let export = CopyExport(doc, selection: NSRange(location: 0, length: doc.length))
        #expect(export.markdown == "> 첫 **줄**\n> 둘째\n본문\n- 토글\n    안")
        #expect(export.html(highlightColors: [:]) == "<meta charset=\"utf-8\">"
            + "<blockquote><p>첫 <strong>줄</strong></p><p>둘째</p></blockquote><p>본문</p>"
            + "<ul><li>토글<p>안</p></li></ul>")
    }

    /// 접기는 토글(`+ `)에만 있다. 인용문은 하위 줄이 있어도 접지 않는다.
    @Test func onlyTogglesFold() {
        let doc = MarkdownDocument("> 인용\n\t안\n+ 토글\n\t안")
        #expect(FoldState.sanitized([0, 2], in: doc) == [2])
    }
}
