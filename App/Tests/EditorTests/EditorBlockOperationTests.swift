import AppKit
import DateTime
import Models
import Testing
@testable import Editor

@MainActor @Suite struct EditorBlockOperationTests {
    private let source = """
    + w.w.w(w)

    [x] w w w w
    \t- w w w
    [x] w w w w
    [ ] w w w w
    [ ] w w w -> w
    [ ] ==w w w w w w w w w -> w w w: w w==
    \t[ ] w w w w w w w w
    [ ] w w
    [ ] w w w w
    """

    @Test func dailyTasksMoveAndFoldAcrossTheBlankSeparator() throws {
        let h = try EditorHarness(source)
        let lines = source.components(separatedBy: "\n")
        let item = ScheduleItem(start: .distantFuture, inlineSource: .init(line: 7, text: lines[7]))
        var note = Note(id: .make(), body: source, schedules: [item], created: .now, modified: .now)
        h.place(at: h.document.lines[2].contentStart, length: h.document.length - h.document.lines[2].contentStart)
        let before = h.editor.selectedRange
        h.press(NSResponder.tab)
        let expected = (Array(lines.prefix(2)) + lines.dropFirst(2).map { "\t" + $0 }).joined(separator: "\n")
        #expect(h.editor.text == expected)
        #expect(h.editor.selectedRange == NSRange(location: before.location + 1, length: before.length + 8))
        #expect(note.applyEditorBody(h.editor.text).isEmpty)
        #expect(note.schedules.first?.inlineSource == .init(line: 7, text: "\t" + lines[7]))
        h.press(NSResponder.backtab)
        #expect(h.editor.text == source && h.editor.selectedRange == before)
        h.undo()
        #expect(h.editor.text == expected)
        h.undo()
        #expect(h.editor.text == source && h.editor.selectedRange == before)
        h.redo()
        let title = h.document.lines[0]
        h.caret(at: title.end)
        h.perform(.toggleDone)
        #expect(FoldState.hiddenLines(h.document, folded: h.editor.foldedLines) == Set(1...10))
        #expect(h.editor.selectedRange.location == title.end && h.editor.text == expected)
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines.isEmpty)
    }

    @Test func groupSkipsBlanksAndNeverMovesOnlySomeLines() throws {
        let h = try EditorHarness.at("- p\n- |a\n\n\t- b|\n- c")
        h.press(NSResponder.tab)
        #expect(h.marked == "- p\n\t- |a\n\n\t\t- b|\n- c")
        h.press(NSResponder.backtab)
        h.press(NSResponder.backtab)
        #expect(h.marked == "- p\n- |a\n\n\t- b|\n- c")
        let depth = String(repeating: "\t", count: MarkdownDocument.maxLevel)
        let atLimit = Scenario("- p\n- |a\n" + depth + "- b|")
        #expect(EditorCommands.indent(atLimit.doc, selection: atLimit.selection) == nil)
    }

    @Test func groupOutdentPreservesMixedWhitespaceDepth() throws {
        let h = try EditorHarness.at("- p\n \t- |a\n \t\t- b|")
        h.press(NSResponder.backtab)
        #expect(h.document.lines.map(\.level) == [0, 0, 1])
        #expect(h.marked == "- p\n - |a\n \t- b|")
    }

    @Test func foldedHeadingMovesWithItsContents() throws {
        let h = try EditorHarness("- 부모\n+ ## 제목\n\n\t- 자식\n꼬리")
        h.caret(atEndOfLine: 1)
        h.perform(.fold)
        h.perform(.indent)
        #expect(h.editor.text == "- 부모\n\t+ ## 제목\n\n\t\t- 자식\n꼬리")
        h.perform(.outdent)
        h.perform(.moveLineDown)
        #expect(h.editor.text == "- 부모\n꼬리\n+ ## 제목\n\n\t- 자식")
        #expect(h.editor.foldedLines == [2])
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines.isEmpty)
    }

    @Test func multipleLinesTakeTabEvenAfterAnActiveDateSuggestion() throws {
        let h = try EditorHarness("+ 제목\n[ ] ==내일 3시==\n[ ] 다음")
        h.editor.onAcceptDate = { _ in
            Issue.record("여러 줄 선택에서 날짜를 수락했습니다")
            return InlineDateEffect(undo: {}, redo: {})
        }
        h.caret(atEndOfLine: 1)
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestion != nil)
        let start = h.document.lines[1].contentStart
        h.place(at: start, length: h.document.length - start)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "+ 제목\n\t[ ] ==내일 3시==\n\t[ ] 다음")
    }

    @Test func doneSkipsEmptyTogglesAndOnlyChecksTodosInMixedSelections() throws {
        let h = try EditorHarness("+ 비어 있음\n[ ] 할 일\n+ 제목\n\t본문")
        h.caret(atEndOfLine: 0)
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines.isEmpty)
        h.place(at: h.document.lines[0].contentStart, length: h.document.length - h.document.lines[0].contentStart)
        h.perform(.toggleDone)
        #expect(h.editor.text == "+ 비어 있음\n[x] 할 일\n+ 제목\n\t본문")
        #expect(h.editor.foldedLines.isEmpty)
    }

    @Test(arguments: [1, 2, 3])
    func headingTogglesKeepTheirLevelAndToggleBehavior(level: Int) throws {
        let hashes = String(repeating: "#", count: level)
        let heading = "+ " + hashes + " 제목"
        let body = heading + "\n\n\t- 자식\n\n끝"
        for marked in [hashes + " >|제목", "+ " + hashes + "|제목"] {
            let s = Scenario(marked)
            let edit = try #require(EditorCommands.spaceTrigger(s.doc, selection: s.selection))
            #expect(edit.applied(to: s.text) == heading)
        }
        let h = try EditorHarness(body)
        let line = h.document.lines[0]
        #expect(line.kind == .toggleHeading(level))
        #expect(h.document.string(in: line.contentRange) == "제목")
        let shown = try h.display(line: 0)
        let attrs = shown.attributes(at: line.contentStart, effectiveRange: nil)
        let font = try #require(attrs[.font] as? NSFont)
        let para = try #require(attrs[.paragraphStyle] as? NSParagraphStyle)
        let deco = try #require(shown.attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        let style = h.controller.style
        #expect(font == style.heading(level).font && para.minimumLineHeight == style.heading(level).lineHeight)
        #expect(para.paragraphSpacingBefore == style.metrics.headingSpacing[level - 1].before)
        #expect(deco.chevronSize == font.pointSize * style.metrics.headingChevronScale)
        #expect(para.headIndent == deco.gutterWidth && deco.gutterWidth > style.gutter)
        let point = try #require(h.controller.gutterPoint(forLine: 0))
        #expect(h.controller.hit(at: point) == .chevron(line: 0))
        h.caret(atEndOfLine: 0)
        h.perform(.toggleDone)
        #expect(FoldState.hiddenLines(h.document, folded: h.editor.foldedLines) == [1, 2])
        h.perform(.unfold)
        #expect(h.editor.foldedLines.isEmpty)
        h.perform(.heading(level))
        #expect(h.document.lines[0].kind == .toggle)
        h.perform(.heading(level))
        #expect(h.editor.text == body)
        let export = CopyExport(source: body)
        #expect(export.markdown.hasPrefix("- " + hashes + " 제목"))
        #expect(export.html(highlightColors: [:]).contains("<h\(level)>제목</h\(level)>"))
        h.caret(at: h.document.lines[0].contentStart)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "제목\n\n- 자식\n\n끝")
    }
}
