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
        let gap = h.theme.component(.editorBlockGap)
        let first = try rowFrame(h, 0), last = try rowFrame(h, 2)
        #expect(parent.minY == first.minY + gap / 2)
        #expect(parent.maxY == last.maxY - gap / 2)
        #expect(parent.minX == h.view.textContainerOrigin.x - 6)
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)))
        let extended = h.controller.blockSelectionRects()
        #expect(extended.first == parent && extended.count == 2)
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
        #expect(rects[1].minY - rects[0].maxY == 2)
        #expect(rects[2].minY - rects[1].maxY == 2)
        #expect(rects[1].height == 22)
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
        let inset = h.theme.component(.editorBlockGap) / 2
        #expect(rects[0].minY == frame.minY + inset)
        #expect(rects[0].maxY == frame.maxY - inset)
    }

    private let week = "[ ] 주간 계획 세우기\n+ 월요일\n\t[ ] 회의록 정리\n\t- 자료 조사\n\t\t- 참고 링크 모으기\n+ 화요일\n\t[ ] 리뷰 답장\n다음 주에 할 것"

    @Test func extendingFromMondayAddsTuesdayThenNextWeekAndShrinksOneBox() throws {
        let h = try EditorHarness(week)
        h.caret(atEndOfLine: 1)
        h.controller.selectBlocks()
        let down = #selector(NSResponder.moveDownAndModifySelection(_:))
        let up = #selector(NSResponder.moveUpAndModifySelection(_:))
        h.press(down)
        #expect(h.controller.blockSelection == BlockSelection(anchor: 1, focus: 5))
        let tuesday = h.controller.blockSelectionRects()
        try #require(tuesday.count == 2)
        let child = try rowFrame(h, 6)
        #expect(tuesday[1].maxY == child.maxY - 1)
        h.press(down)
        #expect(h.controller.blockSelection?.focus == 7)
        #expect(h.controller.blockSelectionRects().count == 3)
        h.press(up)
        #expect(h.controller.blockSelectionRects() == tuesday)
        h.press(up)
        #expect(h.controller.blockSelectionRects() == [tuesday[0]])
    }

    @Test func shiftStopsAtFirstChangedCoverageOrKeepsSelectionAtBoundary() throws {
        let h = try EditorHarness(week)
        // 시안의 각 시작 줄에서 마지막 자식까지의 물리적 줄 번호.
        let ends = [0, 4, 2, 4, 4, 6, 6, 7]
        func coverage(_ anchor: Int, _ focus: Int) -> ClosedRange<Int> {
            let rows = min(anchor, focus)...max(anchor, focus)
            return rows.lowerBound...ends[rows].max()!
        }
        for anchor in ends.indices {
            for focus in ends.indices {
                for direction in [-1, 1] {
                    let start = BlockSelection(anchor: anchor, focus: focus)
                    h.controller.showBlocks(start)
                    let before = h.controller.blockSelectionRects()
                    let rows = coverage(anchor, focus)
                    var expected = focus + direction
                    while ends.indices.contains(expected), coverage(anchor, expected) == rows {
                        expected += direction
                    }
                    h.press(direction < 0 ? #selector(NSResponder.moveUpAndModifySelection(_:))
                                          : #selector(NSResponder.moveDownAndModifySelection(_:)))
                    if ends.indices.contains(expected) {
                        #expect(h.controller.blockSelection == BlockSelection(anchor: anchor, focus: expected))
                        #expect(h.controller.blockSelectionRects() != before)
                    } else {
                        #expect(h.controller.blockSelection == start && h.controller.blockSelectionRects() == before)
                    }
                }
            }
        }
    }

    @Test func plainArrowsEnterChildrenAndShiftTreatsFencedCodeAsOneBlock() throws {
        let h = try EditorHarness("+ 월요일\n\t- 자식\n\t```\n\t내용\n\t```\n+ 접힘\n\t- 숨김\n끝")
        h.editor.foldedLines = [5]
        h.controller.selectBlocks()
        let down = #selector(NSResponder.moveDown(_:))
        h.press(down)
        #expect(h.controller.blockSelection == BlockSelection(anchor: 1, focus: 1))
        h.press(down)
        #expect(h.controller.blockSelection == BlockSelection(anchor: 2, focus: 2))
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)))
        #expect(h.controller.blockSelection == BlockSelection(anchor: 2, focus: 5))
        h.press(down)
        #expect(h.controller.blockSelection == BlockSelection(anchor: 7, focus: 7))
    }

    @Test func tabShiftsEveryPaintedSubtreeAtItsRelativeDepth() throws {
        let h = try EditorHarness(week)
        h.caret(atEndOfLine: 1)
        h.controller.selectBlocks()
        h.press(#selector(NSResponder.moveDownAndModifySelection(_:)))
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.document.lines.map(\.level) == [0, 1, 2, 2, 3, 1, 2, 0])
        h.press(#selector(NSResponder.insertBacktab(_:)))
        #expect(h.editor.text == week)
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
        h.controller.foldAnimationsEnabled = { true }
        var foldHeights: [CGFloat] = []
        h.editor.onContentHeightChange = { [weak h] height in
            if h?.editor.isChangingUserFold == true { foldHeights.append(height) }
        }
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines == [2] && h.editor.text.hasPrefix("[x] A\n[ ] B"))
        #expect(h.controller.currentKeys()[3].isCollapsed)
        #expect(h.controller.foldDrawing.openness[2] == 1)
        #expect(foldHeights == [h.editor.contentHeight])
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

extension BlockSelectionTests {
    @Test func shiftCommandArrowsMoveOnlySelectedBlocks() throws {
        let h = try EditorHarness.at("머리\n+ |제목\n\t안\n끝")
        h.editor.foldedLines = [1]
        #expect(!h.view.canPerformFormat(.moveSelectedBlockUp))
        #expect(!h.key(126, "\u{F700}", [.shift, .command, .numericPad, .function]))
        h.controller.selectBlocks()
        #expect(h.view.canPerformFormat(.moveSelectedBlockUp))
        #expect(h.key(126, "\u{F700}", [.shift, .command, .numericPad, .function]))
        #expect(h.editor.text == "+ 제목\n\t안\n머리\n끝")
        #expect(h.editor.foldedLines == [0])
        #expect(h.key(125, "\u{F701}", [.shift, .command, .numericPad, .function]))
        #expect(h.editor.text == "머리\n+ 제목\n\t안\n끝")
        #expect(h.editor.foldedLines == [1])
    }

    @Test func backspaceAfterBlockCopyAndUndoAfterMarkdownInsertion() throws {
        let h = try EditorHarness.at("- 원본|")
        h.controller.selectBlocks()
        h.step { h.controller.pasteSource("- 사본") }
        #expect(h.controller.blockSelection?.rows == 1...1)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "- 원본")
        h.controller.selectBlocks()
        h.perform(.duplicate)
        #expect(h.controller.blockSelection?.rows == 1...1)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "- 원본")

        let text = try EditorHarness()
        text.step { text.controller.pasteSource("- **글**") }
        #expect(text.document.lines[0].kind == .bullet)
        text.undo()
        #expect(text.editor.text.isEmpty)
        text.type(">")
        text.type(" ")
        text.undo()
        #expect(text.editor.text == ">")
    }

    @Test func backspaceRemovesFormattedTextThenMarkerThenRow() throws {
        for content in ["**글|**", "==글|=={파랑}", "[글|](https://example.org)", "글| <!-- 노랑 바탕 -->"] {
            let h = try EditorHarness.at("위\n[ ] " + content)
            h.press(NSResponder.backspace)
            #expect(h.document.lines.count == 2)
            #expect(h.document.lines[1].kind == .todo(done: false))
            #expect(h.document.lines[1].contentRange.length == 0)
            h.press(NSResponder.backspace)
            #expect(h.document.lines[1].kind == .paragraph)
            h.press(NSResponder.backspace)
            #expect(h.editor.text == "위")
        }
    }
}
