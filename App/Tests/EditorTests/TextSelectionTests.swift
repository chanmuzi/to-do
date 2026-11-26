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

    @Test func selectionPaintsOverFormattingAndReleasesItsOriginalBackground() throws {
        let source = "p p\n==h h h==\n`i i i`\n```\nc c c\n```\n[l l](https://example.com)"
        let h = try EditorHarness(source)
        // 공백 가운데 한 픽셀을 읽어 글자의 안티앨리어싱을 제외한다.
        func pixel(in rect: CGRect) throws -> NSColor {
            let view = h.view
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            let x = Int(rect.midX * CGFloat(image.pixelsWide) / view.bounds.width)
            let y = Int(rect.midY * CGFloat(image.pixelsHigh) / view.bounds.height)
            return try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        for focused in [true, false] {
            if focused { h.editor.focus() } else { h.window.makeFirstResponder(nil) }
            h.place(at: 1, length: 1)
            let plain = try pixel(in: #require(h.controller.selectionRects().first))
            for word in ["h h", "i i", "c c", "l l"] {
                let start = (source as NSString).range(of: word).location + 1
                h.place(at: start, length: 1)
                let rect = try #require(h.controller.selectionRects().first)
                let selected = try pixel(in: rect)
                // 키 창의 반투명 선택 아래에서는 바탕 유무에 따라 픽셀이 달라진다.
                // 비활성 창의 시스템 선택색은 불투명할 수 있다.
                if plain.alphaComponent < 1 && word != "l l" {
                    #expect(selected != plain)
                } else {
                    #expect(selected == plain)
                }
                h.caret(at: 0)
                let released = try pixel(in: rect)
                #expect(released != selected)
                if word != "l l" { #expect(released.alphaComponent > 0) }
            }
        }
        #expect(h.editor.text == source && !h.editor.undoManager.canUndo)
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
