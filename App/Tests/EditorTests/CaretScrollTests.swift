import AppKit
import Testing
@testable import Editor

@MainActor
@Suite struct CaretScrollTests {
    private func editor() throws -> EditorHarness {
        let h = try EditorHarness((1...12).map { "기록 " + String($0) }.joined(separator: "\n"))
        h.window.setContentSize(NSSize(width: 240, height: 92))
        h.window.contentView?.layoutSubtreeIfNeeded()
        h.view.sizeToFit()
        return h
    }

    @Test(arguments: ["+ 토글", "+ # 제목", "- 목록", "- [ ] 체크박스"])
    func arrowNavigationScrollsByVisibleLine(markerLine: String) throws {
        try checkArrows(markerLine: markerLine, folded: false)
    }

    @Test func arrowsSkipFoldedChildren() throws {
        try checkArrows(markerLine: "+ 토글", folded: true)
    }

    private func checkArrows(markerLine: String, folded: Bool) throws {
        let before = (1...4).map { "앞 \($0)" }
        let children = markerLine.hasPrefix("+") ? (1...10).map { "\t자식 \($0)" } : []
        let after = (1...8).map { "뒤 \($0)" }
        let rows = before + [markerLine] + children + after
        let h = try EditorHarness(rows.joined(separator: "\n"), width: 240)
        if folded { h.editor.foldedLines = [before.count] }
        h.window.setContentSize(NSSize(width: 240, height: 120))
        h.window.contentView?.layoutSubtreeIfNeeded()
        h.view.sizeToFit()
        h.caret(at: 0)

        let room = h.theme.component(.editorCaretScrollRoom)
        let scale = h.window.backingScaleFactor
        let hiddenRows = (before.count + 1)..<(before.count + 1 + children.count)
        let visibleRows = rows.indices.filter { !folded || !hiddenRows.contains($0) }
        // 맨 아래 여백을 모두 보이는 마지막 줄은 기존 입력 테스트에서 따로 확인한다.
        let route = Array(visibleRows.dropLast())
        for (key, destinations) in [(NSResponder.down, Array(route.dropFirst())),
                                    (NSResponder.up, Array(route.dropLast().reversed()))] {
            for row in destinations {
                let previous = h.view.visibleRect.minY
                let previousLine = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
                h.press(key)
                let selection = h.view.selectedRange()
                let line = try #require(h.controller.segmentRects(for: selection).last)
                let visible = h.view.visibleRect
                #expect(selection.length == 0)
                #expect(h.document.lineIndex(at: selection.location) == row)
                // 제목 앞뒤의 문단 간격을 포함한 화면 한 줄의 실제 이동 거리를 잰다.
                let step = key == NSResponder.down ? line.maxY - previousLine.maxY : previousLine.minY - line.minY
                #expect(abs(visible.minY - previous) <= ceil(step * scale) / scale)
                #expect(line.minY - visible.minY >= room)
                #expect(visible.maxY - line.maxY >= room)
            }
        }
    }

    @Test func rightArrowIntoFinalListItemExposesDocumentEnd() throws {
        let h = try editor()
        h.editor.text += "\n- 목록"
        h.caret(atEndOfLine: h.document.lines.count - 2)
        h.view.scrollRangeToVisible(h.view.selectedRange())
        h.press(NSResponder.right)
        let item = try #require(h.document.lines.last)
        #expect(h.view.selectedRange() == NSRange(location: item.caretStart, length: 0))
        #expect(h.view.visibleRect.maxY == h.view.bounds.maxY)

        // 이동 명령이 끝나면 같은 줄의 기호나 다른 줄을 찾아 보이라는 요청은 원래 범위를 따른다.
        for location in [item.start, h.document.lines[0].start] {
            #expect(h.controller.caretScrollTarget(for: NSRange(location: location, length: 0)) == nil)
        }
        #expect(h.controller.caretScrollTarget(for: item.fullRange) == nil)
    }

    @Test func lastLineEditsExposeDocumentEnd() throws {
        let h = try editor()
        h.caret(at: h.document.length)
        h.press(NSResponder.newline)
        h.paste(String(repeating: "자동 줄바꿈 ", count: 14))
        #expect(h.view.visibleRect.maxY == h.view.bounds.maxY)
        h.mark("글")
        #expect(h.view.hasMarkedText())
        #expect(h.view.visibleRect.minY > 0)
        #expect(h.view.visibleRect.maxY == h.view.bounds.maxY)
        let line = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
        #expect(h.view.visibleRect.maxY - line.maxY >= h.theme.docPadding.bottom - 1)
    }

    @Test func emptyCheckboxAfterReturnAndEarlierWrappedLine() throws {
        let h = try editor()
        h.editor.text = h.editor.text + "\n- [ ] 정리"
        h.caret(at: h.document.length)
        h.press(NSResponder.newline)
        #expect(h.document.lines.last?.kind == .todo(done: false))
        #expect(h.view.visibleRect.maxY == h.view.bounds.maxY)
        let last = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
        #expect(abs(h.view.visibleRect.maxY - last.maxY - 12) <= 1)
        h.paste(String(repeating: "다음 문장 ", count: 90))
        let paragraph = try #require(h.document.lines.last)
        h.caret(at: paragraph.contentStart + 4)
        h.type("첫")
        #expect(h.view.visibleRect.maxY < h.view.bounds.maxY)
        let line = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
        #expect(line.minY - h.view.visibleRect.minY >= h.theme.component(.editorCaretScrollRoom) - 1)
    }

    @Test func middleLinesHaveRoomInBothDirections() throws {
        let h = try editor()
        let room: CGFloat = 6
        for index in [8, 3] {
            h.caret(atEndOfLine: index)
            h.type("가")
            let line = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
            #expect(line.minY - h.view.visibleRect.minY >= room - 1)
            #expect(h.view.visibleRect.maxY - line.maxY >= room - 1)
            let target = try #require(h.controller.caretScrollTarget(for: h.view.selectedRange()))
            #expect(abs(line.minY - target.minY - room) <= 1)
            #expect(abs(target.maxY - line.maxY - room) <= 1)
            let visible = h.view.visibleRect
            h.type("나")
            #expect(h.view.visibleRect == visible)
        }
    }
}
