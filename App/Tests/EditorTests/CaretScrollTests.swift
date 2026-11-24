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
        #expect(h.view.visibleRect.maxY - last.maxY >= h.theme.docPadding.bottom - 1)
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
        let room = h.theme.component(.editorCaretScrollRoom)
        for index in [8, 3] {
            h.caret(atEndOfLine: index)
            h.type("가")
            let line = try #require(h.controller.segmentRects(for: h.view.selectedRange()).last)
            #expect(line.minY - h.view.visibleRect.minY >= room - 1)
            #expect(h.view.visibleRect.maxY - line.maxY >= room - 1)
            let visible = h.view.visibleRect
            h.type("나")
            #expect(h.view.visibleRect == visible)
        }
    }
}
