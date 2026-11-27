import AppKit
import Testing
import Theme
@testable import Editor

@MainActor
@Suite struct MarkdownEditorDisplayTests {
    private let hidden = EditorMetrics.hiddenFontSize

    @Test func togglingInkInvalidatesTheLayerThatDrawsItsBackground() throws {
        let previousInk = EditorController.lastInk
        defer { EditorController.lastInk = previousInk }
        EditorController.lastInk = InkColor(.yellow)
        let h = try EditorHarness.at("첫 |문단| 끝")
        let root = try #require(h.window.contentView)
        root.wantsLayer = true
        h.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        h.window.orderBack(nil)
        defer { h.window.orderOut(nil) }
        root.layoutSubtreeIfNeeded()
        h.window.displayIfNeeded()
        CATransaction.flush()
        let layer = try #require(h.view.layer)
        for highlighted in [true, false] {
            h.window.displayIfNeeded()
            layer.displayIfNeeded()
            #expect(!layer.needsDisplay())
            h.perform(.highlight)
            #expect(layer.needsDisplay() || h.view.needsDisplay)
            let manager = h.controller.layoutManager
            let fragment = try #require(manager.textLayoutFragment(for: manager.documentRange.location))
            let paragraph = try #require(fragment.textElement as? NSTextParagraph).attributedString
            let selected = (paragraph.string as NSString).range(of: "문단")
            #expect((paragraph.attribute(.markdownHighlight, at: selected.location, effectiveRange: nil) != nil) == highlighted)
        }
    }

    @Test func displayedParagraphHasTheSameCharactersAsTheSource() throws {
        let h = try EditorHarness(DemoNote.text)
        for index in h.document.lines.indices {
            let shown = try h.display(line: index)
            #expect(shown.string == h.document.string(in: h.document.lines[index].fullRange))
        }
    }

    @Test func inlineMarkersStayHiddenOnTheCaretLineToo() throws {
        let h = try EditorHarness(DemoNote.text)
        let bold = h.document.lines[1].spans[0]       // **PR #482**
        let highlight = h.document.lines[4].spans[0]  // ==배포 체크리스트 확인==

        for line in [4, 1] {
            h.caret(atEndOfLine: line)
            #expect(try h.fontSize(line: 4, at: highlight.openMarker) == [hidden, hidden])
            #expect(try h.fontSize(line: 4, at: highlight.closeMarker) == [hidden, hidden])
            #expect(try h.color(line: 4, at: highlight.openMarker.location) == .clear)
            #expect(try h.fontSize(line: 1, at: bold.openMarker) == [hidden, hidden])
            #expect(try h.fontSize(line: 1, at: bold.closeMarker) == [hidden, hidden])
        }
        // 커서를 구간 안에 두어도, 선택해도 같다.
        h.controller.setSelection(NSRange(location: bold.contentRange.location + 1, length: 0))
        #expect(try h.fontSize(line: 1, at: bold.openMarker) == [hidden, hidden])
        h.controller.setSelection(bold.range)
        #expect(try h.fontSize(line: 1, at: bold.closeMarker) == [hidden, hidden])
        #expect(h.editor.text == DemoNote.text)
    }

    @Test func movingTheCaretRestylesNothing() throws {
        let h = try EditorHarness(DemoNote.text)
        let before = h.controller.currentKeys()
        h.caret(atEndOfLine: 4)
        #expect(h.controller.currentKeys() == before)
        h.window.makeFirstResponder(nil)
        #expect(h.controller.currentKeys() == before)
    }

    @Test func listMarkersAreAlwaysReplacedByTheGutter() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 2)
        let line = h.document.lines[2] // "\t[ ] 포커스…"
        #expect(try h.fontSize(line: 2, at: line.prefixRange).allSatisfy { $0 == hidden })
        let decoration = try #require(try h.display(line: 2).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(decoration.gutter == .checkbox(done: false))
        #expect(decoration.gutterX == h.theme.component(.indent))
        let style = try #require(try h.display(line: 2).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent == h.theme.component(.indent) + h.theme.component(.gutter))
        #expect(style.minimumLineHeight == h.theme.lineHeight(.body))
    }

    @Test func checkboxHoverUsesTheClickableGutterOnly() throws {
        let h = try EditorHarness("[ ] 열린 일\n[x] 끝낸 일")
        let controller = h.editor.controller
        for line in 0...1 {
            let point = try #require(controller.gutterPoint(forLine: line))
            #expect(controller.handleMouseMoved(at: point))
            #expect(controller.hoveredGutterLine == line)
            #expect(controller.gutterHover.frame.width == h.theme.component(.checkSize) + h.theme.space(.sp1) * 2)
            let text = try #require(controller.textPoint(forLine: line))
            #expect(!controller.handleMouseMoved(at: text))
            #expect(controller.hoveredGutterLine == nil)
        }
        #expect(h.editor.text == "[ ] 열린 일\n[x] 끝낸 일")
    }

    @Test func chevronHoverFramesCenterOnTheGlyphAndFitTheFirstLine() throws {
        let h = try EditorHarness("+ 본문 토글\n\t+ ## 제목 토글")
        let controller = h.controller
        for padding in [h.theme.space(.sp1), h.theme.space(.sp4)] {
            try h.theme.setOverrides(ThemeOverrides(values: ["space.sp-1": "\(padding)px"]))
            for (line, role) in [(0, TextStyle.body), (1, .h2)] {
                let style = controller.style
                let size = line == 0 ? style.metrics.chevronSize : style.heading(2).font.pointSize * style.metrics.headingChevronScale
                let left = h.view.textContainerOrigin.x + CGFloat(line) * style.indent
                let text = try #require(controller.textPoint(forLine: line))
                let center = CGPoint(x: left + (style.checkSize - style.metrics.chevronSize + size) / 2, y: text.y)
                #expect(controller.handleMouseMoved(at: center))
                let hover = controller.gutterHover
                let rect = h.view.convert(hover.bounds, from: hover)
                let side = min(size + padding * 2, h.theme.lineHeight(role))
                #expect(rect == CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
                #expect(hover.alphaValue == 1)
                #expect(hover.superview === h.view.superview)
            }
        }
    }

    @Test func chevronHoverStaysThroughFoldingAndHidesDuringBlockSelection() throws {
        let h = try EditorHarness("+ 본문\n\t자식\n+ ## 제목\n\t자식")
        let controller = h.controller
        for row in [0, 2] {
            let point = try #require(controller.gutterPoint(forLine: row))
            #expect(controller.handleMouseMoved(at: point))
            let frame = controller.gutterHover.frame
            for folded in [true, false] {
                #expect(controller.handleMouseDown(at: point))
                #expect(controller.folded.contains(row) == folded)
                #expect(controller.hoveredGutterLine == row)
                #expect(controller.gutterHover.frame == frame)
                #expect(controller.gutterHover.alphaValue == 1)
            }
            controller.showBlocks(BlockSelection(anchor: row, focus: row))
            #expect(controller.hoveredGutterLine == nil)
            #expect(controller.gutterHover.alphaValue == 0)
            #expect(controller.handleMouseMoved(at: point))
            #expect(controller.hoveredGutterLine == nil)
            #expect(controller.clearBlocks())
            #expect(controller.handleMouseMoved(at: point))
            controller.handleMouseExited()
            #expect(controller.gutterHover.alphaValue == 0)
        }
    }

    @Test func gutterGlyphsPerKindAndLevel() throws {
        let h = try EditorHarness("- 0\n\t- 1\n\t\t- 2\n\t\t\t- 3\n+ 토글\n\t하위\n[x] 끝")
        func gutter(_ line: Int) throws -> FragmentDecoration.Gutter? {
            (try h.display(line: line).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)?.gutter
        }
        #expect(try gutter(0) == .bullet(0))
        #expect(try gutter(1) == .bullet(1))
        #expect(try gutter(2) == .bullet(2))
        #expect(try gutter(3) == .bullet(0))
        #expect(try gutter(4) == .chevron(open: true))
        #expect(try gutter(5) == nil)
        #expect(try gutter(6) == .checkbox(done: true))
        h.editor.foldedLines = [4]
        #expect(try gutter(4) == .chevron(open: false))
    }

    @Test func headingMarkerIsAlwaysHidden() throws {
        let h = try EditorHarness("# 제목\n본문")
        for line in [1, 0] {
            h.caret(atEndOfLine: line)
            #expect(try h.fontSize(line: 0, at: NSRange(location: 0, length: 2)) == [hidden, hidden])
            #expect(try h.fontSize(line: 0, at: NSRange(location: 2, length: 1)) == [h.theme.nsFont(.h1).pointSize])
        }
    }

    @Test func linkShowsOnlyItsText() throws {
        let h = try EditorHarness("[글자](https://a.example/b) 뒤")
        let span = h.document.lines[0].spans[0]
        h.caret(atEndOfLine: 0)
        #expect(try h.fontSize(line: 0, at: span.openMarker) == [hidden])
        #expect(try h.fontSize(line: 0, at: span.closeMarker).allSatisfy { $0 == hidden })
        #expect(try h.fontSize(line: 0, at: span.contentRange).allSatisfy { $0 == h.theme.nsFont(.body).pointSize })
    }

    @Test func linkInkWinsOverNestedColorsAndPreservesBackgroundOnHover() throws {
        let h = try EditorHarness()
        for source in ["==[문서](https://example.com)=={빨강 글자}", "[==문서=={빨강 글자}](https://example.com)",
                       "==[문서](https://example.com)=={파랑}", "+ [문서](https://example.com) <!-- 초록 글자 -->"] {
            h.editor.text = source
            let span = try #require(h.document.lines[0].spans.first { if case .link = $0.kind { true } else { false } })
            for hovered in [false, true] {
                h.controller.hoveredLink = hovered ? (0, span.range.location) : nil
                h.controller.refreshStyling()
                let display = try h.display(line: 0)
                let attributes = display.attributes(at: (source as NSString).range(of: "문서").location, effectiveRange: nil)
                let style = h.controller.style
                #expect(attributes[.foregroundColor] as? NSColor == (hovered ? style.text : style.text2))
                #expect(attributes[.underlineColor] as? NSColor == (hovered ? style.text2 : style.text3))
                #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
                #expect((attributes[.markdownHighlight] != nil) == source.hasSuffix("{파랑}"))
            }
        }
    }

    @Test func inlineStyles() throws {
        let text = "**굵게** ~~취소~~ ==색=={3} `코드` [링크](https://a.example)"
        let h = try EditorHarness(text + "\n")
        h.caret(atEndOfLine: 1)
        let shown = try h.display(line: 0)
        let spans = h.document.lines[0].spans
        func attributes(_ index: Int) -> [NSAttributedString.Key: Any] {
            shown.attributes(at: spans[index].contentRange.location, effectiveRange: nil)
        }
        #expect((attributes(0)[.font] as? NSFont) == h.theme.nsFont(.strong))
        #expect(attributes(1)[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes(1)[.foregroundColor] as? NSColor == h.theme.rgba(.text2).nsColor)
        #expect((attributes(2)[.markdownHighlight] as? InlineBackground)?.kind == .highlight(3))
        #expect(attributes(2)[.foregroundColor] as? NSColor == h.theme.rgba(.text).nsColor)
        #expect((attributes(3)[.font] as? NSFont) == h.theme.nsFont(.code))
        let box = try #require(attributes(3)[.markdownCodeBox] as? InlineBackground)
        #expect(box.kind == .code)
        #expect(box.height == h.theme.component(.codeHeight))
        #expect(box.padX == h.theme.component(.codePaddingX))
        #expect(box.drop == h.theme.component(.codeDrop))
        // 인라인 코드의 글자는 기본으로 코드 강조색이다(D-035).
        #expect(attributes(3)[.foregroundColor] as? NSColor == h.theme.rgba(.codeAccent).nsColor)
        #expect(attributes(4)[.markdownLink] as? String == "https://a.example")
        #expect(attributes(4)[.underlineColor] as? NSColor == h.theme.rgba(.text3).nsColor)
        // 형광펜의 색 번호도 닫는 기호와 함께 감춘다.
        #expect(try h.fontSize(line: 0, at: spans[2].closeMarker).allSatisfy { $0 == hidden })
    }

    @Test func togglingHighlightPreservesGlyphPositions() throws {
        for prefix in ["", "[x] "] {
            let h = try EditorHarness(prefix + "가나다 노랑 바탕 라마바\n\n")
            func positions() throws -> [CGFloat] {
                h.window.layoutIfNeeded()
                let manager = h.controller.layoutManager
                manager.ensureLayout(for: manager.documentRange)
                let fragment = try #require(manager.textLayoutFragment(for: manager.documentRange.location))
                let line = try #require(fragment.textLineFragments.first)
                let text = h.editor.text as NSString
                return ["가", "노", "탕", "라", "바"].map {
                    line.locationForCharacter(at: text.range(of: $0).location).x
                }
            }
            let original = h.editor.text
            let before = try positions()
            h.editor.selectedRange = (original as NSString).range(of: "노랑 바탕")
            for highlighted in [true, false] {
                h.controller.setInk(InkColor(.yellow), toggle: true)
                #expect(h.document.lines[0].spans.isEmpty == !highlighted)
                for (x, y) in zip(try positions(), before) {
                    #expect(abs(x - y) < 0.1)
                }
            }
            #expect(h.editor.text == original)
        }
    }

    @Test func adjacentHighlightsMeetWithoutDoublePaintingTheirPadding() throws {
        let h = try EditorHarness("==노랑=={노랑}==파랑=={파랑}")
        let manager = h.controller.layoutManager
        manager.ensureLayout(for: manager.documentRange)
        let fragment = try #require(manager.textLayoutFragment(for: manager.documentRange.location) as? MarkdownLayoutFragment)
        let text = try #require((fragment.textElement as? NSTextParagraph)?.attributedString)
        let boxes = fragment.inlineBoxes(for: .markdownHighlight, in: text)
        try #require(boxes.count == 2)
        #expect(abs(boxes[0].0.maxX - boxes[1].0.minX) < 0.001)
    }

    @Test func editorSelectionUsesConfirmedBlueInEachAppearance() throws {
        let h = try EditorHarness("본문")
        let color = try #require(h.view.selectedTextAttributes[.backgroundColor] as? NSColor)
        for mode in ThemeAppearance.allCases {
            let appearance = try #require(NSAppearance(named: mode == .light ? .aqua : .darkAqua))
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
            let selection = try #require(resolved)
            #expect(abs(selection.redComponent * 255 - 35) < 0.01)
            #expect(abs(selection.greenComponent * 255 - 131) < 0.01)
            #expect(abs(selection.blueComponent * 255 - 226) < 0.01)
            #expect(abs(selection.alphaComponent - (mode == .light ? 0.14 : 0.26)) < 0.001)
        }
    }

    @Test(arguments: ThemeAppearance.allCases)
    func blockSelectionPreservesCompletedBlockColor(appearance: ThemeAppearance) throws {
        let h = try EditorHarness("[x] 완료 <!-- 노랑 바탕 -->\n[x] 완료", appearance: appearance)
        h.window.appearance = appearance.nsAppearance
        h.controller.blockSelection = BlockSelection(anchor: 0, focus: 1)
        let boxes = h.controller.blockSelectionRects()
        try #require(boxes.count == 2)
        // 같은 선택 안에서 글자가 없는 두 블록의 중앙 픽셀을 비교한다.
        let image = try #require(h.view.bitmapImageRepForCachingDisplay(in: h.view.bounds))
        h.view.cacheDisplay(in: h.view.bounds, to: image)
        func fill(_ rect: CGRect) throws -> NSColor {
            let x = Int(rect.midX * CGFloat(image.pixelsWide) / h.view.bounds.width)
            let y = Int(rect.midY * CGFloat(image.pixelsHigh) / h.view.bounds.height)
            return try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        let colored = try fill(boxes[0]), plain = try fill(boxes[1])
        #expect(plain.alphaComponent > 0 && plain.alphaComponent < 1)
        #expect(colored.alphaComponent > plain.alphaComponent && colored != plain)
    }

    @Test(arguments: ThemeAppearance.allCases)
    func wrappedHighlightFadesAndRestoresWhenToggled(appearance: ThemeAppearance) throws {
        let h = try EditorHarness("- [ ] ==긴 체크박스에서 줄바꿈 뒤에도 색을 유지하는 글을 확인합니다=={4}", width: 155, appearance: appearance)
        h.caret(atEndOfLine: 0)
        for done in [false, true, false] {
            if case .todo(let value) = h.document.lines[0].kind, value != done { h.perform(.toggleDone) }
            let manager = h.controller.layoutManager
            manager.ensureLayout(for: manager.documentRange)
            let fragment = try #require(manager.textLayoutFragment(for: manager.documentRange.location) as? MarkdownLayoutFragment)
            let shown = try #require((fragment.textElement as? NSTextParagraph)?.attributedString)
            var range = NSRange()
            let bg = try #require(shown.attribute(.markdownHighlight, at: (shown.string as NSString).range(of: "긴").location,
                                                  effectiveRange: &range) as? InlineBackground)
            let normal = h.controller.style.ink(InkColor(.blue)).alphaComponent
            #expect(abs(bg.color.alphaComponent - normal * (done ? h.theme.ratio(.doneFade) : 1)) < 0.001)
            let boxes = fragment.backgroundRects(for: range, background: bg)
            #expect(boxes.count > 1)
            for (box, line) in zip(boxes.dropFirst(), fragment.textLineFragments.dropFirst()) {
                #expect(box.minX >= line.typographicBounds.minX)
            }
        }
    }

    @Test func doneTodoIsDimmedAndStruck() throws {
        let h = try EditorHarness("[x] 끝낸 **일**")
        let shown = try h.display(line: 0)
        let attributes = shown.attributes(at: 4, effectiveRange: nil)
        #expect(attributes[.foregroundColor] as? NSColor == h.theme.rgba(.text3).nsColor)
        #expect(attributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func inlineCodeStyleSwitchesTheTextColorOnly() throws {
        let h = try EditorHarness("앞 `코드` 뒤\n```\nlet x = 1\n```")
        let content = h.document.lines[0].spans[0].contentRange.location
        #expect(h.editor.configuration.inlineCodeStyle == .accent)
        #expect(try h.color(line: 0, at: content) == h.theme.rgba(.codeAccent).nsColor)
        let box = try h.display(line: 0).attribute(.markdownCodeBox, at: content, effectiveRange: nil) as? InlineBackground

        h.editor.configuration.inlineCodeStyle = .plain
        #expect(try h.color(line: 0, at: content) == h.theme.rgba(.codeForeground).nsColor)
        let plainBox = try h.display(line: 0).attribute(.markdownCodeBox, at: content, effectiveRange: nil) as? InlineBackground
        #expect(plainBox?.height == box?.height)
        #expect(plainBox?.padX == box?.padX)
        // 코드 블록의 글자는 어느 쪽에서도 무채색이다.
        #expect(try h.color(line: 2, at: h.document.lines[2].start) == h.theme.rgba(.codeForeground).nsColor)
        h.editor.configuration.inlineCodeStyle = .accent
        #expect(try h.color(line: 2, at: h.document.lines[2].start) == h.theme.rgba(.codeForeground).nsColor)
    }

    @Test func inlineCodeInsideOtherElements() throws {
        let h = try EditorHarness("# 제목 `a`\n[x] 끝낸 `b`\n==형광 `c` 안==")
        func attributes(_ line: Int) throws -> [NSAttributedString.Key: Any] {
            let span = try #require(h.document.lines[line].spans.first { $0.kind == .code })
            return try h.display(line: line).attributes(at: span.contentRange.location - h.document.lines[line].start, effectiveRange: nil)
        }
        // 제목 안에서는 제목 크기에 비례해 커지고 상자도 따라 커진다.
        let heading = try attributes(0)
        let scale = h.theme.nsFont(.h1).pointSize / h.theme.nsFont(.body).pointSize
        #expect((heading[.font] as? NSFont)?.pointSize == (h.theme.nsFont(.code).pointSize * scale * 2).rounded() / 2)
        #expect((heading[.markdownCodeBox] as? InlineBackground)?.height == (h.theme.component(.codeHeight) * scale).rounded())
        // 끝낸 투두 안에서는 흐린 색에 취소선이고 상자는 그대로다.
        let done = try attributes(1)
        #expect(done[.foregroundColor] as? NSColor == h.theme.rgba(.text3).nsColor)
        #expect(done[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(done[.markdownCodeBox] is InlineBackground)
        // 형광펜 안에서는 형광펜 바탕 위에 코드 상자가 함께 놓인다.
        let highlighted = try attributes(2)
        #expect((highlighted[.markdownHighlight] as? InlineBackground)?.kind == .highlight(1))
        #expect((highlighted[.markdownCodeBox] as? InlineBackground)?.kind == .code)
    }

    @Test func codeBlockFencesAreAlwaysCollapsed() throws {
        let h = try EditorHarness("앞\n```swift\n// 주석\nlet x = 1\n```\n뒤")
        func lineHeight(_ line: Int) throws -> CGFloat {
            let style = try #require(try h.display(line: line).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            return style.maximumLineHeight
        }
        // 커서가 블록 밖에 있든 안에 있든 ``` 줄(언어 이름 포함)은 보이지 않고 상자의 안쪽 여백만 차지한다.
        for line in [0, 3] {
            h.caret(atEndOfLine: line)
            #expect(try lineHeight(1) == h.theme.component(.codeBlockPaddingY))
            #expect(try lineHeight(4) == h.theme.component(.codeBlockPaddingY))
            #expect(try h.color(line: 1, at: h.document.lines[1].start) == .clear)
            #expect(try h.fontSize(line: 1, at: h.document.lines[1].range).allSatisfy { $0 == hidden })
            #expect(try h.color(line: 4, at: h.document.lines[4].start) == .clear)
            #expect(try lineHeight(3) == h.theme.lineHeight(.codeBlock))
            #expect(try h.color(line: 2, at: h.document.lines[2].start) == h.theme.rgba(.text3).nsColor)
            #expect(try h.color(line: 3, at: h.document.lines[3].start) == h.theme.rgba(.codeForeground).nsColor)
        }
    }

    @Test func linesWithCodeFontKeepTheirExactHeight() throws {
        // 글꼴의 leading이 줄 높이에 더해지지 않는다(D2Coding이 든 줄이 20.96, 코드 줄이 18.96이 되던 문제).
        let h = try EditorHarness("본문\n본문 `코드` 본문\n```\nlet x = 1\nlet y = 2\n```\n뒤")
        h.window.layoutIfNeeded()
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        var heights: [CGFloat] = []
        h.controller.layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            heights.append(fragment.layoutFragmentFrame.height)
            return true
        }
        let body = h.theme.lineHeight(.body)
        let code = h.theme.lineHeight(.codeBlock)
        let pad = h.theme.component(.codeBlockPaddingY)
        let gap = h.theme.component(.codeBlockGap)
        #expect(heights == [body, body, pad + gap, code, code, pad + gap, body])
    }

    @Test func bracketCheckboxWidensTheGutter() throws {
        let h = try EditorHarness("[ ] 할 일", checkbox: .bracket)
        func headIndent() throws -> CGFloat {
            try #require(try h.display(line: 0).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle).headIndent
        }
        #expect(try headIndent() == h.controller.style.metrics.bracketGutter)
        h.editor.configuration.checkboxStyle = .box
        #expect(try headIndent() == h.theme.component(.gutter))
    }
}

@MainActor
@Suite struct MarkdownEditorLayoutTests {
    @Test func contentHeightFollowsTheLines() throws {
        let h = try EditorHarness("하나")
        let padding = h.theme.docPadding
        let line = h.theme.lineHeight(.body)
        #expect(h.editor.contentHeight == padding.top + padding.bottom + line)
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.newline)
        h.type("둘")
        #expect(h.editor.contentHeight == padding.top + padding.bottom + line * 2)
        #expect(h.heights.last == padding.top + padding.bottom + line * 2)
    }

    @Test func longDocumentReportsExactHeightAfterWrappingAndFolding() throws {
        let wrapped = String(repeating: "길게 감기는 본문 ", count: 12)
        let blocks = (0..<150).map { _ in "# 제목\n+ 토글\n\t" + wrapped }
        let h = try EditorHarness(blocks.joined(separator: "\n") + "\n", width: 220)
        let editor = h.controller
        func checkHeight() {
            let reported = editor.lastContentHeight
            editor.layoutManager.ensureLayout(for: editor.layoutManager.documentRange)
            var bottom: CGFloat = 0
            editor.layoutManager.enumerateTextLayoutFragments(from: editor.layoutManager.documentRange.endLocation,
                                                               options: [.reverse, .ensuresLayout]) { fragment in
                bottom = fragment.layoutFragmentFrame.maxY
                return false
            }
            let padding = h.theme.docPadding
            #expect(reported == ceil(bottom) + padding.top + padding.bottom)
        }
        checkHeight()
        editor.toggleFold(line: 1)
        checkHeight()
        h.caret(atEndOfLine: 227)
        h.type("가")
        checkHeight()
        editor.toggleFold(line: 1)
        checkHeight()
    }

    @Test func emptyNoteIsOneLineTall() throws {
        let h = try EditorHarness("")
        let padding = h.theme.docPadding
        #expect(h.editor.contentHeight == padding.top + padding.bottom + h.theme.lineHeight(.body))
    }

    @Test func foldingHidesTheChildrenWithoutChangingTheText() throws {
        let h = try EditorHarness(DemoNote.text)
        let line = h.theme.lineHeight(.body)
        let open = h.editor.contentHeight
        h.editor.foldedLines = [5]
        // 넣을 때는 알리지 않는다.
        #expect(h.foldChanges.isEmpty)
        // 접힌 줄은 높이가 0.01씩 남아, 올림한 높이가 1pt까지 어긋날 수 있다.
        #expect(abs(h.editor.contentHeight - (open - line * 4)) <= 1)
        #expect(h.editor.text == DemoNote.text)
        let collapsed = try #require(try h.display(line: 7).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(collapsed.maximumLineHeight == EditorMetrics.collapsedLineHeight)

        h.editor.foldedLines = []
        #expect(h.editor.contentHeight == open)
    }

    @Test func chevronClickAndShortcutFoldAndUnfold() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 7)
        let point = try #require(h.controller.gutterPoint(forLine: 5))
        #expect(h.controller.hit(at: point) == .chevron(line: 5))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(h.editor.foldedLines == [5])
        // 접힌 줄 안에 있던 커서는 토글 제목 끝으로 나온다.
        #expect(h.editor.selectedRange == NSRange(location: h.document.lines[5].end, length: 0))
        h.perform(.unfold)
        #expect(h.editor.foldedLines == [])
        h.caret(atEndOfLine: 8)
        h.perform(.fold)
        #expect(h.editor.foldedLines == [5])
        #expect(h.foldChanges == [[5], [], [5]])
        #expect(h.editor.text == DemoNote.text)
    }

    @Test func typingAfterAFoldedToggleStaysVisible() throws {
        let h = try EditorHarness("+ 토글\n\t- 안\n밖")
        h.editor.foldedLines = [0]
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.newline)
        h.type("새 토글")
        #expect(h.editor.text == "+ 토글\n\t- 안\n+ 새 토글\n밖")
        #expect(h.editor.foldedLines == [0, 2])
        // 접힌 줄과 맞닿은 줄바꿈을 지우려 하면 먼저 편다(보이지 않는 줄과 합쳐지지 않게).
        h.caret(atEndOfLine: 3)
        h.editor.selectedRange = NSRange(location: h.document.lines[3].start, length: 0)
        h.perform(.moveLineUp)
        #expect(h.editor.text == "+ 토글\n\t- 안\n밖\n+ 새 토글")
        #expect(!h.controller.textView(h.view, doCommandBy: NSResponder.backspace))
        #expect(h.editor.foldedLines == [3])
    }

    @Test func linkClickOpensTheAddress() throws {
        let h = try EditorHarness("본문 [문서](https://a.example/x) 끝\n")
        h.caret(atEndOfLine: 1)
        var opened: [URL] = []
        h.editor.onOpenLink = { opened.append($0) }
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        let location = try #require(h.controller.contentStorage.location(h.controller.contentStorage.documentRange.location, offsetBy: 0))
        let fragment = try #require(h.controller.layoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment)
        let span = h.document.lines[0].spans[0]
        let rect = try #require(fragment.rects(for: span.contentRange).first)
        let origin = h.view.textContainerOrigin
        let frame = fragment.layoutFragmentFrame
        let point = CGPoint(x: origin.x + frame.minX + rect.midX, y: origin.y + frame.minY + rect.midY)
        #expect(h.controller.isInteractive(at: point))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(opened == [URL(string: "https://a.example/x")!])
        // 링크 밖은 보통의 글자다.
        #expect(!h.controller.isInteractive(at: CGPoint(x: origin.x + 2, y: point.y)))
    }
}

@MainActor
@Suite struct MarkdownEditorPasteboardTests {
    /// 사용자의 클립보드를 건드리지 않도록 이름을 붙인 클립보드를 쓴다.
    private func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("floating-notes-tests-\(UUID().uuidString)"))
    }

    @Test func copyPutsMarkdownHTMLAndSourceOnThePasteboard() throws {
        let h = try EditorHarness(DemoNote.text)
        let board = pasteboard()
        defer { board.releaseGlobally() }
        h.editor.selectedRange = NSRange(location: 0, length: h.document.length)
        #expect(h.controller.copySelection(to: board))
        let markdown = try #require(board.string(forType: .string))
        #expect(markdown.hasPrefix("- [x] 스탠드업 회의록 공유\n- [ ] **PR #482** 리뷰\n\t- [ ] 포커스"))
        #expect(markdown.contains("- 지난주에서 넘어온 것\n\t- [ ] **온보딩 문서**"))
        let html = try #require(board.string(forType: .html))
        #expect(html.contains("<mark class=\"highlight-yellow_background\" style=\"background-color:#FBF3DB\">배포 체크리스트 확인</mark>"))
        #expect(html.contains("<summary>지난주에서 넘어온 것</summary><ul class=\"to-do-list\"><li>"))
        #expect(board.string(forType: .floatingNotesMarkdown) == DemoNote.text)
    }

    @Test func nothingIsCopiedWithoutASelection() throws {
        let h = try EditorHarness("가")
        let board = pasteboard()
        defer { board.releaseGlobally() }
        #expect(!h.controller.copySelection(to: board))
    }

    @Test func pastingInsideTheAppRoundTripsTheSyntax() throws {
        let source = "+ 토글\n\t[ ] ==형광=={3}\n\t[x] 끝"
        let from = try EditorHarness(source)
        let board = pasteboard()
        defer { board.releaseGlobally() }
        from.editor.selectedRange = NSRange(location: 0, length: from.document.length)
        from.controller.copySelection(to: board)

        let to = try EditorHarness()
        to.step { to.controller.paste(from: board) }
        #expect(to.editor.text == source)
        #expect(to.changes == [source])
        to.editor.undoManager.undo()
        #expect(to.editor.text == "")
    }

    @Test func pastingPlainTextFromAnotherApp() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("- [ ] 표준 투두\nhttps://a.example", forType: .string)
        let h = try EditorHarness()
        h.step { h.controller.paste(from: board) }
        #expect(h.document.lines[0].kind == .todo(done: false))
        // 붙여 넣은 주소는 링크가 된다.
        #expect(h.document.lines[1].spans.map(\.kind) == [.link("https://a.example")])
    }

    @Test func codeBlockCopyButtonCopiesTheCode() throws {
        let h = try EditorHarness("```swift\nlet a = 1\nlet b = 2\n```")
        let board = pasteboard()
        defer { board.releaseGlobally() }
        h.controller.codePasteboard = board
        h.controller.setHoveredCodeBlock(0...3)
        h.controller.copyButton.onPress?()
        #expect(board.string(forType: .string) == "let a = 1\nlet b = 2")
        #expect(h.controller.copyButton.accessibilityLabel() == "복사")
    }
}

extension MarkdownEditorDisplayTests {
    @Test func emptyToggleHintRequiresOpeningAnUnrecordedToggle() throws {
        let h = try EditorHarness("+ ## A\n+ B")
        #expect(h.controller.currentKeys().allSatisfy { $0.isFolded && !$0.showsEmptyToggleHint })
        let point = try #require(h.controller.gutterPoint(forLine: 0))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(h.editor.openedEmptyToggleLines == [0])
        #expect(h.controller.currentKeys()[0].showsEmptyToggleHint)
        h.caret(atEndOfLine: 0)
        h.controller.selectBlocks()
        h.perform(.toggleDone)
        #expect(h.editor.openedEmptyToggleLines.isEmpty)
        #expect(!h.controller.currentKeys()[0].showsEmptyToggleHint)
        h.perform(.toggleDone)
        #expect(h.editor.openedEmptyToggleLines == [0])
        h.perform(.moveSelectedBlockDown)
        #expect(h.editor.openedEmptyToggleLines == [1])
        h.undo()
        #expect(h.editor.openedEmptyToggleLines == [0])
        h.redo()
        #expect(h.editor.openedEmptyToggleLines == [1])
    }

    @Test func emptyToggleHintReservesOneRowAndCreatesAChild() throws {
        for suffix in ["", "\n다음"] {
            let h = try EditorHarness("+ " + suffix)
            h.place(at: 2)
            h.editor.foldedLines = [0]
            let closed = h.controller.measureContentHeight()
            h.perform(.toggleDone)
            let open = h.controller.measureContentHeight()
            #expect(abs(open - closed - h.controller.style.body.lineHeight) <= 1)
            let layout = h.controller.layoutManager
            let fragment = try #require(layout.textLayoutFragment(for: layout.documentRange.location) as? MarkdownLayoutFragment)
            #expect(fragment.decoration?.showsTogglePlaceholder == true)
            #expect(h.view.accessibilityHelp()?.contains(FragmentDecoration.emptyToggleHint) == true)
            #expect(h.editor.text == "+ " + suffix)
            let rect = try #require(fragment.emptyToggleHintRect)
            h.controller.selectBlocks()
            let box = try #require(h.controller.blockSelectionRects().first)
            let origin = h.view.textContainerOrigin
            #expect(box.maxY <= fragment.layoutFragmentFrame.minY + origin.y + rect.minY)
            let point = CGPoint(x: rect.midX + fragment.layoutFragmentFrame.minX + origin.x,
                                y: rect.midY + fragment.layoutFragmentFrame.minY + origin.y)
            #expect(h.controller.handleMouseDown(at: point))
            #expect(h.marked == "+ \n\t|" + suffix)
            #expect(!h.controller.currentKeys()[0].showsEmptyToggleHint)
            #expect(h.editor.openedEmptyToggleLines.isEmpty)
            h.undo()
            #expect(h.editor.openedEmptyToggleLines == [0])
        }
    }
}
