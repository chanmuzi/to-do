import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct TextSelectionTests {
    @Test func selectionUsesGlyphBoundsAndPreservesSourceAndExport() throws {
        let source = "# 제목\n짧은 **글자**와 `code`\n\n- 목록\n- [ ] 확인\n> 인용\n```swift\na()\n\nb()\n```\n끝\n"
        let h = try EditorHarness(source)
        h.view.selectAll(nil)
        let selection = h.editor.selectedRange
        let export = CopyExport(h.document, selection: selection)
        let rects = h.controller.selectionRects()
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.width > 0 && $0.width < 150 && $0.height < 26 })
        #expect(h.editor.text == source)
        #expect(h.editor.selectedRange == selection)
        #expect(CopyExport(h.document, selection: selection).source == export.source)
        #expect(CopyExport(h.document, selection: selection).markdown == export.markdown)
        #expect(!h.editor.undoManager.canUndo)
        var rendered: [CGRect] = []
        h.controller.layoutManager.enumerateTextSegments(in: h.controller.contentStorage.documentRange,
            type: .selection, options: []) { range, rect, _, _ in
                #expect(range != nil)
                rendered.append(rect)
                return true
            }
        #expect(rendered.count == rects.count)
        #expect(rendered.allSatisfy { $0.width < 150 })
    }

    @Test func newlineOnlyAndHiddenMarkersHaveNoPaint() throws {
        let h = try EditorHarness("a\n\n**b**\n```\nc\n```\n")
        for range in [NSRange(location: 1, length: 2), NSRange(location: 3, length: 2), NSRange(location: 9, length: 3)] {
            h.controller.setSelection(range)
            #expect(h.controller.selectionRects().isEmpty)
        }
    }

    @Test func selectionDoesNotCoverListOrQuoteDecoration() throws {
        for source in ["- item", "- [ ] item", "> item"] {
            let h = try EditorHarness(source)
            h.view.selectAll(nil)
            let rects = h.controller.selectionRects()
            #expect(!rects.isEmpty)
            let padding = source.hasPrefix(">") ? h.controller.style.quotePadding : h.controller.style.gutter
            #expect(rects.allSatisfy { $0.minX >= h.view.textContainerOrigin.x + padding })
        }
    }

    @Test func wrappedUnicodeAndBidirectionalTextRemainFinite() throws {
        let source = String(repeating: "한글 👨‍👩‍👧‍👦 abc אבג ", count: 12)
        let h = try EditorHarness(source, width: 260)
        h.view.selectAll(nil)
        let rects = h.controller.selectionRects()
        #expect(rects.count > 3)
        #expect(rects.allSatisfy { $0.width.isFinite && $0.width > 0 && $0.width <= h.controller.textContainer.size.width })
        #expect(h.editor.text == source)
        h.controller.setSelection(NSRange(location: 0, length: 0))
        #expect(h.controller.selectionRects().isEmpty)
    }
}
