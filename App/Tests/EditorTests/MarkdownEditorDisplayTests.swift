import AppKit
import Testing
import Theme
@testable import Editor

@MainActor
@Suite struct MarkdownEditorDisplayTests {
    private let hidden = EditorMetrics.hiddenFontSize

    @Test func displayedParagraphHasTheSameCharactersAsTheSource() throws {
        let h = try EditorHarness(DemoNote.text)
        for index in h.document.lines.indices {
            let shown = try h.display(line: index)
            #expect(shown.string == h.document.string(in: h.document.lines[index].fullRange))
        }
    }

    @Test func inlineMarkersShowOnlyOnTheCaretLine() throws {
        let h = try EditorHarness(DemoNote.text)
        let bold = h.document.lines[1].spans[0]       // **PR #482**
        let highlight = h.document.lines[4].spans[0]  // ==배포 체크리스트 확인==
        let syntaxSize = h.theme.nsFont(.code).pointSize

        h.caret(atEndOfLine: 4)
        #expect(try h.fontSize(line: 4, at: highlight.openMarker) == [syntaxSize, syntaxSize])
        #expect(try h.fontSize(line: 4, at: highlight.closeMarker) == [syntaxSize, syntaxSize])
        #expect(try h.color(line: 4, at: highlight.openMarker.location) == h.theme.rgba(.text3).nsColor)
        #expect(try h.fontSize(line: 1, at: bold.openMarker) == [hidden, hidden])
        #expect(try h.fontSize(line: 1, at: bold.closeMarker) == [hidden, hidden])

        // 커서가 떠나면 사라지고, 옮겨 간 줄에서 나타난다.
        h.caret(atEndOfLine: 1)
        #expect(try h.fontSize(line: 4, at: highlight.openMarker) == [hidden, hidden])
        #expect(try h.color(line: 4, at: highlight.openMarker.location) == .clear)
        #expect(try h.fontSize(line: 1, at: bold.openMarker) == [syntaxSize, syntaxSize])
        #expect(h.editor.text == DemoNote.text)
    }

    @Test func markersHideWhenTheEditorLosesFocus() throws {
        let h = try EditorHarness(DemoNote.text)
        let highlight = h.document.lines[4].spans[0]
        h.caret(atEndOfLine: 4)
        #expect(try h.fontSize(line: 4, at: highlight.openMarker).allSatisfy { $0 > 1 })
        h.window.makeFirstResponder(nil)
        #expect(try h.fontSize(line: 4, at: highlight.openMarker) == [hidden, hidden])
    }

    @Test func listMarkersAreAlwaysReplacedByTheGutter() throws {
        let h = try EditorHarness(DemoNote.text)
        h.caret(atEndOfLine: 2)
        let line = h.document.lines[2] // "\t[ ] 포커스…"
        #expect(try h.fontSize(line: 2, at: line.prefixRange).allSatisfy { $0 == hidden })
        let decoration = try #require(try h.display(line: 2).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(decoration.gutter == .checkbox(done: false))
        #expect(decoration.gutterX == h.theme.component(.indent))
        #expect(decoration.guideCount == 1)
        let style = try #require(try h.display(line: 2).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent == h.theme.component(.indent) + h.theme.component(.gutter))
        #expect(style.minimumLineHeight == h.theme.lineHeight(.body))
    }

    @Test func gutterGlyphsPerKindAndLevel() throws {
        let h = try EditorHarness("- 0\n\t- 1\n\t\t- 2\n\t\t\t- 3\n> 토글\n\t하위\n[x] 끝")
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

    @Test func headingMarkerShowsOnlyWhileEditing() throws {
        let h = try EditorHarness("# 제목\n본문")
        h.caret(atEndOfLine: 1)
        #expect(try h.fontSize(line: 0, at: NSRange(location: 0, length: 2)) == [hidden, hidden])
        #expect(try h.fontSize(line: 0, at: NSRange(location: 2, length: 1)) == [h.theme.nsFont(.h1).pointSize])
        h.caret(atEndOfLine: 0)
        #expect(try h.fontSize(line: 0, at: NSRange(location: 0, length: 1)) == [h.theme.nsFont(.code).pointSize])
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
        #expect((attributes(2)[.markdownInlineBackground] as? InlineBackground)?.kind == .highlight(3))
        #expect(attributes(2)[.foregroundColor] as? NSColor == h.theme.rgba(HighlightColor.rose.foreground).nsColor)
        #expect((attributes(3)[.font] as? NSFont) == h.theme.nsFont(.code))
        #expect((attributes(3)[.markdownInlineBackground] as? InlineBackground)?.kind == .code)
        #expect(attributes(4)[.markdownLink] as? String == "https://a.example")
        #expect(attributes(4)[.underlineColor] as? NSColor == h.theme.rgba(.text3).nsColor)
        // 형광펜의 색 번호도 닫는 기호와 함께 감춘다.
        #expect(try h.fontSize(line: 0, at: spans[2].closeMarker).allSatisfy { $0 == hidden })
    }

    @Test func doneTodoIsDimmedAndStruck() throws {
        let h = try EditorHarness("[x] 끝낸 **일**")
        let shown = try h.display(line: 0)
        let attributes = shown.attributes(at: 4, effectiveRange: nil)
        #expect(attributes[.foregroundColor] as? NSColor == h.theme.rgba(.text3).nsColor)
        #expect(attributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func codeBlockFencesCollapseUnlessTheCaretIsInside() throws {
        let h = try EditorHarness("앞\n```swift\n// 주석\nlet x = 1\n```\n뒤")
        func lineHeight(_ line: Int) throws -> CGFloat {
            let style = try #require(try h.display(line: line).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            return style.maximumLineHeight
        }
        h.caret(atEndOfLine: 0)
        #expect(try lineHeight(1) == EditorMetrics.codeBlockPadY)
        #expect(try h.color(line: 1, at: h.document.lines[1].start) == .clear)
        #expect(try lineHeight(3) == EditorMetrics.codeLineHeight)
        #expect(try h.color(line: 2, at: h.document.lines[2].start) == h.theme.rgba(.text3).nsColor)
        #expect(try h.color(line: 3, at: h.document.lines[3].start) == h.theme.rgba(.codeForeground).nsColor)

        h.caret(atEndOfLine: 3)
        #expect(try lineHeight(1) == EditorMetrics.codeLineHeight + EditorMetrics.codeBlockPadY)
        #expect(try h.color(line: 1, at: h.document.lines[1].start) == h.theme.rgba(.text3).nsColor)
        #expect(try h.color(line: 4, at: h.document.lines[4].start) == h.theme.rgba(.text3).nsColor)
    }

    @Test func bracketCheckboxWidensTheGutter() throws {
        let h = try EditorHarness("[ ] 할 일", checkbox: .bracket)
        func headIndent() throws -> CGFloat {
            try #require(try h.display(line: 0).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle).headIndent
        }
        #expect(try headIndent() == EditorMetrics.bracketGutter)
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
        #expect(abs(h.editor.contentHeight - (open - line * 4)) < 1)
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
        let h = try EditorHarness("> 토글\n\t- 안\n밖")
        h.editor.foldedLines = [0]
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.newline)
        h.type("새 토글")
        #expect(h.editor.text == "> 토글\n\t- 안\n> 새 토글\n밖")
        #expect(h.editor.foldedLines == [0])
        // 접힌 줄과 맞닿은 줄바꿈을 지우려 하면 먼저 편다(보이지 않는 줄과 합쳐지지 않게).
        h.caret(atEndOfLine: 3)
        h.editor.selectedRange = NSRange(location: h.document.lines[3].start, length: 0)
        h.perform(.moveLineUp)
        #expect(h.editor.text == "> 토글\n\t- 안\n밖\n> 새 토글")
        #expect(!h.controller.textView(h.view, doCommandBy: NSResponder.backspace))
        #expect(h.editor.foldedLines == [])
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
        #expect(markdown.hasPrefix("- [x] 스탠드업 회의록 공유\n- [ ] **PR #482** 리뷰\n    - [ ] 포커스"))
        #expect(markdown.contains("- 지난주에서 넘어온 것\n    - [ ] **온보딩 문서**"))
        let html = try #require(board.string(forType: .html))
        #expect(html.contains("<mark style=\"background-color:#FFEB85\">배포 체크리스트 확인</mark>"))
        #expect(html.contains("<li>지난주에서 넘어온 것<ul><li>"))
        #expect(board.string(forType: .floatingNotesMarkdown) == DemoNote.text)
    }

    @Test func nothingIsCopiedWithoutASelection() throws {
        let h = try EditorHarness("가")
        let board = pasteboard()
        defer { board.releaseGlobally() }
        #expect(!h.controller.copySelection(to: board))
    }

    @Test func pastingInsideTheAppRoundTripsTheSyntax() throws {
        let source = "> 토글\n\t[ ] ==형광=={3}\n\t[x] 끝"
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
