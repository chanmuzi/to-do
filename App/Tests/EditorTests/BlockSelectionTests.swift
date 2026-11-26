import AppKit
import DateTime
import Models
import Theme
import Testing
@testable import Editor

@MainActor @Suite struct BlockSelectionTests {
    private func rowFrame(_ h: EditorHarness, _ row: Int) throws -> CGRect {
        let controller = h.controller
        controller.layoutManager.ensureLayout(for: controller.layoutManager.documentRange)
        let location = try #require(controller.contentStorage.location(controller.contentStorage.documentRange.location,
                                                                       offsetBy: h.document.lines[row].start))
        let fragment = try #require(controller.layoutManager.textLayoutFragment(for: location))
        return fragment.layoutFragmentFrame.offsetBy(dx: h.view.textContainerOrigin.x, dy: h.view.textContainerOrigin.y)
    }

    @Test func parentSelectionCoversVisibleChildrenOnce() throws {
        let h = try EditorHarness("+ ### [기획](https://example.com)\n\t- 첫째\n\t- 둘째\n- 다음")
        h.caret(atEndOfLine: 0)
        h.controller.selectBlocks()
        let parent = try #require(h.controller.blockSelectionRects().first)
        let gap = h.theme.space(.sp1)
        let first = try rowFrame(h, 0), last = try rowFrame(h, 2)
        #expect(parent.minY == first.minY + gap / 2)
        #expect(parent.maxY == last.maxY - gap / 2)
        #expect(parent.minX == h.view.textContainerOrigin.x - gap)
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)), times: 2)
        #expect(h.controller.blockSelectionRects() == [parent])
        h.controller.blockSelection = BlockSelection(anchor: 2, focus: 1)
        let children = h.controller.blockSelectionRects()
        try #require(children.count == 2)
        #expect(children.allSatisfy { $0.minX == parent.minX + h.controller.style.indent })
        #expect(children[1].minY - children[0].maxY == gap)
    }

    @Test func mixedSiblingsShareOneGapAndReserveOnlyTheMarkedBlocksMargin() throws {
        let h = try EditorHarness("앞\n+ ### 제목\n- 항목\n문단")
        let now = Date()
        let item = ScheduleItem(start: now, inlineSource: .init(line: 2, text: "- 항목"))
        let note = Note(id: .make(), body: h.editor.text, schedules: [item], created: now, modified: now)
        h.editor.setScheduleMarkers(ScheduleLineMarker.markers(in: note, now: now, options: .init(), calendar: .current))
        h.controller.blockSelection = BlockSelection(anchor: 1, focus: 3)
        let rects = h.controller.blockSelectionRects()
        try #require(rects.count == 3)
        #expect(rects[1].minY - rects[0].maxY == h.theme.space(.sp1))
        #expect(rects[2].minY - rects[1].maxY == h.theme.space(.sp1))
        #expect(rects[0].maxX == rects[2].maxX)
        #expect(rects[0].maxX - rects[1].maxX == h.theme.component(.noteTopButtonSize))
    }

    @Test func foldedToggleSelectionStopsAtItsOwnRow() throws {
        let h = try EditorHarness("+ ### 제목\n\t- 숨긴 자식\n다음")
        h.editor.foldedLines = [0]
        h.controller.selectBlocks()
        let rects = h.controller.blockSelectionRects()
        try #require(rects.count == 1)
        let frame = try rowFrame(h, 0)
        let inset = h.theme.space(.sp1) / 2
        #expect(rects[0].minY == frame.minY + inset)
        #expect(rects[0].maxY == frame.maxY - inset)
    }

    @Test func navigationExtendsAndShrinksAcrossVisibleBlocks() throws {
        let h = try EditorHarness("- 첫 줄\\\n둘째\n+ 접음\n\t안쪽\n끝")
        h.editor.foldedLines = [2]
        h.caret(atEndOfLine: 1)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.controller.blockSelection == BlockSelection(anchor: 0, focus: 0))
        #expect(h.controller.caretRect() == nil)
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)), times: 2)
        #expect(h.controller.blockSelection == BlockSelection(anchor: 0, focus: 4))
        h.press(#selector(NSResponder.moveUpAndModifySelection(_:)))
        #expect(h.controller.blockSelection?.focus == 2)
        h.press(#selector(NSResponder.moveUp(_:)))
        #expect(h.controller.blockSelection?.rows == 0...0)
        h.press(#selector(NSResponder.moveDown(_:)))
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.controller.blockSelection == nil)
        #expect(h.editor.selectedRange.location == h.document.lines[2].end)
    }

    @Test func duplicateAndDeleteCarryTheSubtreeOnce() throws {
        let h = try EditorHarness("앞\n+ 부모\\\n이어짐\n\t- 자식\n뒤")
        h.editor.foldedLines = [1]
        h.caret(atEndOfLine: 2)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.perform(.duplicate)
        #expect(h.editor.text == "앞\n+ 부모\\\n이어짐\n\t- 자식\n+ 부모\\\n이어짐\n\t- 자식\n뒤")
        #expect(h.editor.foldedLines == [1, 4])
        #expect(h.controller.blockSelection?.rows == 4...4)
        h.press(#selector(NSResponder.deleteForward(_:)))
        #expect(h.editor.text == "앞\n+ 부모\\\n이어짐\n\t- 자식\n뒤")
        h.undo()
        #expect(h.editor.foldedLines == [1, 4])
        h.undo()
        #expect(h.editor.foldedLines == [1])
    }

    @Test func textSelectionBecomesBlocksAndTypingOnlyDismisses() throws {
        let source = "하나\n둘\\\n이어짐\n셋"
        let h = try EditorHarness(source)
        h.place(at: 1, length: 5)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.controller.blockSelection?.rows == 0...1)
        h.type("X")
        #expect(h.controller.blockSelection == nil && h.editor.text == source)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.view.selectAll(nil)
        #expect(h.editor.selectedRange == NSRange(location: 0, length: source.utf16.count))
        #expect(h.controller.blockSelection == nil)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.editor.text == "")
        h.undo()
        #expect(h.editor.text == source)
    }

    @Test func blockCommandsPreserveSelectionAndRelativeDepth() throws {
        let h = try EditorHarness("- 부모\n[ ] 일\\\n추가\n- 이웃\n끝")
        h.caret(atEndOfLine: 2)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)))
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.editor.text == "- 부모\n\t[ ] 일\\\n\t추가\n\t- 이웃\n끝")
        h.press(#selector(NSResponder.insertBacktab(_:)))
        h.perform(.toggleDone)
        h.perform(.moveLineDown)
        #expect(h.editor.text == "- 부모\n끝\n[x] 일\\\n추가\n- 이웃")
        #expect(h.controller.blockSelection?.rows == 2...4)
        h.perform(.moveLineUp)
        #expect(h.controller.blockSelection?.rows == 1...3)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.editor.selectedRange.location == h.document.lines[2].end)
        h.press(#selector(NSResponder.cancelOperation(_:)), times: 2)
        #expect(h.controller.blockSelection == nil)
    }

    @Test func selectedParentIncludesAllChildrenAndSwapsWholeNeighbor() throws {
        let h = try EditorHarness("+ A\n\t- 첫째\n\t- 둘째\n+ B\n\t- 하나\n\t- 둘")
        h.caret(atEndOfLine: 0)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)))
        h.perform(.moveLineDown)
        #expect(h.editor.text == "+ B\n\t- 하나\n\t- 둘\n+ A\n\t- 첫째\n\t- 둘째")
        h.perform(.moveLineUp)
        #expect(h.editor.text.hasPrefix("+ A\n\t- 첫째\n\t- 둘째"))
        h.perform(.duplicate)
        #expect(h.editor.text.hasPrefix("+ A\n\t- 첫째\n\t- 둘째\n+ A\n\t- 첫째\n\t- 둘째"))
    }

    @Test func selectedTogglesAndMixedTodosChangeTogether() throws {
        let h = try EditorHarness("[ ] A\n[x] B\n+ 토글\n\t자식")
        h.caret(atEndOfLine: 0)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)), times: 2)
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines == [2] && h.editor.text.hasPrefix("[x] A\n[ ] B"))
        h.undo()
        #expect(h.editor.foldedLines.isEmpty && h.editor.text.hasPrefix("[ ] A\n[x] B"))
    }

    @Test func typingCaretFollowsTheCopy() throws {
        let h = try EditorHarness.at("[ ] 회의\\\n나|중\n끝")
        h.perform(.duplicate)
        #expect(h.marked == "[ ] 회의\\\n나중\n[ ] 회의\\\n나|중\n끝")
        h.undo()
        #expect(h.marked == "[ ] 회의\\\n나|중\n끝")
    }
}

@MainActor @Suite struct LineBreakTests {
    @Test func breakAtCaretRoundTripsAndReturnStartsAnotherTodo() throws {
        let h = try EditorHarness.at("\t[x] 첫|둘")
        h.press(#selector(NSResponder.insertLineBreak(_:)))
        #expect(h.marked == "\t[x] 첫\\\n\t|둘")
        #expect(h.document.blockLines(at: 1) == 0...1)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.marked == "\t[x] 첫|둘")
        h.undo()
        h.caret(atEndOfLine: 1)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.marked == "\t[x] 첫\\\n\t둘\n\t[ ] |")
    }

    @Test func markerIsHiddenAndStyleContinuesWithoutASecondGlyph() throws {
        let h = try EditorHarness("[x] 첫\\\n다음\n+ ## 제목\\\n뒷줄")
        for row in [0, 2] {
            let first = try h.display(line: row), next = try h.display(line: row + 1)
            let a = try #require(first.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let b = try #require(next.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(a.firstLineHeadIndent == b.firstLineHeadIndent)
            #expect(h.controller.gutterPoint(forLine: row + 1) == nil)
            #expect(try h.color(line: row, at: h.document.lines[row].contentEnd) == NSColor.clear)
            #expect(try h.fontSize(line: row, at: h.document.lines[row].contentRange).first ==
                    h.fontSize(line: row + 1, at: h.document.lines[row + 1].contentRange).first)
        }
        #expect(try h.display(line: 1).attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)
        h.caret(atEndOfLine: 1)
        h.perform(.toggleDone)
        #expect(h.editor.text.hasPrefix("[ ]"))
    }

    @Test func literalEscapesCodeAndNestedChildrenStayDistinct() {
        let doc = MarkdownDocument("짝수\\\\\n다음\n```\n코드\\\n코드\n```\n+ 제목\\\n계속\n\t자식\n끝\\")
        #expect(doc.lines.indices.filter { doc.lines[$0].hasHardBreak } == [6])
        #expect(doc.lines[7].continuationOf == 6)
        #expect(FoldState.hiddenLines(doc, folded: [6]) == [8])
        #expect(doc.lines[3].kind == .code && doc.lines[9].contentEnd == doc.length)
    }

    @Test func lineBreakAtLastEmptyCodeLineStaysInsideFence() throws {
        let h = try EditorHarness.at("```\ncode\n|\n```")
        h.press(#selector(NSResponder.insertLineBreak(_:)))
        #expect(h.marked == "```\ncode\n\n|\n```")
    }

    @Test func oldBackslashBeforeCodeFenceAndMarkdownListInterruptions() {
        let doc = MarkdownDocument("기록\\\n```\n코드\\\n```")
        #expect(!doc.lines[0].hasHardBreak && doc.lines[1].kind == .fenceOpen && doc.lines[2].kind == .code)
        #expect(CopyExport(source: "[ ] 일정\\\n1. 발송").markdown == "- [ ] 일정<br>1. 발송")
    }

    @Test func exportsOneListItemAndOneMultilineHeading() {
        let export = CopyExport(source: "[ ] 첫\\\n둘\n## 제목\\\n다음")
        #expect(export.markdown == "- [ ] 첫\\\n  둘\n## 제목<br>다음")
        let html = export.html(highlightColors: [:])
        #expect(html.contains("첫<br>둘</li>"))
        #expect(html.contains("<h2>제목<br>다음</h2>"))
    }

    @Test func blockDateIsAcceptedFromEitherLineAndEscapeDismissesFirst() throws {
        let h = try EditorHarness("[ ] 회의\\\n내일 자료")
        var request: InlineDateAcceptance?
        h.editor.onAcceptDate = { request = $0; return InlineDateEffect(undo: {}, redo: {}) }
        h.caret(at: h.document.lines[0].contentStart)
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestion != nil)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.controller.dateSuggestion == nil && h.controller.blockSelection == nil)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.controller.blockSelection?.rows == 0...0)
        h.controller.clearBlocks()
        h.controller.scheduleRemoved(fromBodyLine: 0)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(request?.source.line == 0 && request?.source.text == "[ ] 회의\\\n자료")
        #expect(h.editor.text == request?.nextText)
        h.undo()
        #expect(h.editor.text == "[ ] 회의\\\n내일 자료")
    }
}
