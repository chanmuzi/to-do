import AppKit
import Testing
import Theme
@testable import Editor

/// 얇은 입력 커서(D-042): 너비 `caret-w`, 색 `accent`, 높이는 커서 자리 글꼴의 ascender부터 descender까지.
@MainActor
@Suite struct CaretTests {
    private func caret(_ h: EditorHarness) throws -> TextCaret {
        try #require(h.view.caret)
    }

    private func boxHeight(_ font: NSFont) -> CGFloat { font.ascender - font.descender }

    /// 커서가 놓일 글자 경계의 x(텍스트 뷰 좌표). 시스템이 아는 자리와 견준다.
    private func glyphX(_ h: EditorHarness, at location: Int) -> CGFloat {
        let screen = h.view.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        let inWindow = h.window.convertFromScreen(screen)
        return h.view.convert(inWindow, from: nil).minX
    }

    @Test func zoomScalesBodyHeadingsAndCodeWithinTheEditor() throws {
        let h = try EditorHarness("# 제목\n## 제목\n### 제목\n본문\n`코드`")
        func sizes() throws -> [CGFloat] {
            try [2, 3, 4, 0, 1].enumerated().map { line, offset in
                let paragraph = try h.display(line: line)
                return try #require(paragraph.attribute(.font, at: offset, effectiveRange: nil) as? NSFont).pointSize
            }
        }
        let before = try sizes()
        let titleFont = h.theme.nsFont(.title)
        try h.theme.applyBodyTypography(size: Int(h.theme.component(.settingsFontMax)), lineHeight: nil)
        #expect(try zip(sizes(), before).allSatisfy { $0 > $1 })
        #expect(h.theme.nsFont(.title) == titleFont)
    }

    @Test func thinAccentCaretWithTheBodyGlyphHeight() throws {
        let h = try EditorHarness.at("본문 글자|")
        let caret = try caret(h)
        #expect(caret.isActive)
        let scale = h.window.backingScaleFactor
        #expect(caret.frame.width == (h.theme.component(.caretWidth) * scale).rounded() / scale)
        #expect(abs(caret.frame.height - boxHeight(h.controller.style.body.font)) <= 1)
        #expect(caret.frame.height < h.theme.lineHeight(.body))
        #expect(caret.color == h.theme.rgba(.accent).nsColor)
        #expect(abs(caret.frame.midX - glyphX(h, at: h.editor.selectedRange.location)) <= 1)
    }

    /// 시스템의 커서 표시는 만들어지지 않는다(두 커서가 겹치거나 자국이 남지 않게).
    @Test func noSystemInsertionIndicatorIsCreated() throws {
        let h = try EditorHarness.at("본문|")
        h.type("가")
        h.press(NSResponder.left)
        func indicators(_ view: NSView) -> Int {
            (view is NSTextInsertionIndicator ? 1 : 0) + view.subviews.map(indicators).reduce(0, +)
        }
        #expect(indicators(h.window.contentView!) == 0)
    }

    @Test func headingCaretIsTallerAndInlineCodeCaretShorter() throws {
        let h = try EditorHarness("# 큰 제목\n본문 `코드` 끝")
        h.caret(atEndOfLine: 0)
        let heading = try caret(h).frame
        #expect(abs(heading.height - boxHeight(h.controller.style.heading(1).font)) <= 1)
        let code = h.document.lines[1].spans[0].contentRange
        h.place(at: code.location + 1)
        let inCode = try caret(h).frame
        #expect(abs(inCode.height - boxHeight(h.controller.style.inlineCode)) <= 1)
        h.place(at: h.document.lines[1].end)
        let body = try caret(h).frame
        #expect(heading.height > body.height)
        #expect(inCode.height < body.height)
        // 인라인 코드의 커서는 그 줄 안에 든다.
        #expect(inCode.minY >= body.minY - 1 && inCode.maxY <= body.maxY + 1)
    }

    @Test func codeBlockCaretUsesTheCodeFont() throws {
        let h = try EditorHarness("```\nlet x = 1\n```")
        h.caret(atEndOfLine: 1)
        #expect(abs(try caret(h).frame.height - boxHeight(h.controller.style.codeBlock.font)) <= 1)
        #expect(abs(try caret(h).frame.midX - glyphX(h, at: h.document.lines[1].end)) <= 1)
    }

    @Test func emptyLinesHaveACaretToo() throws {
        let h = try EditorHarness("위\n\n아래\n")
        h.caret(atEndOfLine: 1)
        #expect(try caret(h).isActive)
        let middle = try caret(h).frame
        #expect(abs(middle.height - boxHeight(h.controller.style.body.font)) <= 1)
        // 문서 끝의 빈 줄(문단이 따로 없다).
        h.caret(atEndOfLine: 3)
        #expect(try caret(h).isActive)
        #expect(try caret(h).frame.minY > middle.maxY)
    }

    /// 줄이 넘어간 경계: End로 온 커서(앞쪽에 붙음)는 윗줄 끝에, 뒤쪽에 붙은 커서는 아랫줄 앞에 놓인다.
    @Test func wrappedLineBoundaryFollowsTheAffinity() throws {
        let h = try EditorHarness(String(repeating: "가나다라 ", count: 30), width: 200)
        h.place(at: 0)
        h.press(NSResponder.end)
        let location = h.editor.selectedRange.location
        #expect(h.view.selectionAffinity == .upstream)
        let end = try caret(h).frame
        h.view.setSelectedRange(NSRange(location: location, length: 0), affinity: .downstream, stillSelecting: false)
        let next = try caret(h).frame
        #expect(next.minY > end.maxY)
        #expect(next.minX < end.minX)
        #expect(abs(next.minX - (try caret(h).frame.minX)) == 0)
        h.press(NSResponder.home)
        #expect(abs(try caret(h).frame.minX - next.minX) <= 1)
    }

    @Test func hiddenWithASelectionAndWithoutFocus() throws {
        let h = try EditorHarness.at("본문 |글자|")
        #expect(try !caret(h).isActive)
        h.place(at: 2)
        #expect(try caret(h).isActive)
        h.window.makeFirstResponder(nil)
        #expect(try !caret(h).isActive)
        h.editor.focus()
        #expect(try caret(h).isActive)
        // 키 창이 아닌 창에서는 보이지 않는다.
        h.controller.forcesActiveAppearance = false
        #expect(!h.window.isKeyWindow)
        #expect(try !caret(h).isActive)
    }

    @Test func followsTypingUndoAndComposition() throws {
        let h = try EditorHarness.at("가|")
        let before = try caret(h).frame
        h.type("나다")
        let typed = try caret(h).frame
        #expect(typed.minX > before.minX)
        #expect(abs(typed.midX - glyphX(h, at: h.editor.selectedRange.location)) <= 1)
        h.mark("ㄹ")
        let composing = try caret(h)
        #expect(composing.isActive)
        #expect(composing.frame.minX > typed.minX)
        h.commit("라")
        h.undo()
        #expect(abs(try caret(h).frame.midX - glyphX(h, at: h.editor.selectedRange.location)) <= 1)
    }

    @Test func blinksAndRestartsOnTyping() throws {
        let h = try EditorHarness.at("가|")
        let caret = try caret(h)
        #expect(!caret.isBlinkedOff)
        RunLoop.main.run(until: Date().addingTimeInterval(h.theme.motion.caretBlink + 0.15))
        #expect(caret.isBlinkedOff)
        h.type("나")
        #expect(!caret.isBlinkedOff)
    }

    /// 테마의 강조색을 바꾸면 떠 있는 커서도 바로 바뀐다.
    @Test func followsTheThemeLive() throws {
        let h = try EditorHarness.at("가|")
        try h.theme.setOverrides(ThemeOverrides(values: ["color.light.accent": "#00AA00", "color.dark.accent": "#00AA00"]))
        #expect(try caret(h).color == h.theme.rgba(.accent).nsColor)
        #expect(h.theme.rgba(.accent).nsColor.greenComponent > 0.6)
    }
}

extension CaretTests {
    @Test(arguments: ["|", "앞줄\n|", "앞줄\n\n|", "앞줄\n|\n끝", "- |", "[ ] |", "[x] |"], [false, true])
    func emptyAndTypedCaretShareLineGeometry(source: String, resized: Bool) throws {
        let h = try EditorHarness.at(source)
        if resized { try h.theme.applyBodyTypography(size: 18, lineHeight: 30) }
        func rect() throws -> NSRect {
            h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
            return try #require(h.controller.caretRect())
        }
        func inputRect() -> NSRect {
            h.view.firstRect(forCharacterRange: h.editor.selectedRange, actualRange: nil)
        }
        let empty = try rect()
        let emptyInput = inputRect()
        h.type("가")
        let typed = try rect()
        let typedInput = inputRect()
        #expect(typedInput.height > 0)
        #expect(emptyInput.minY == typedInput.minY && emptyInput.height == typedInput.height)
        #expect(abs(empty.minY - typed.minY) < 0.01)
        #expect(abs(empty.height - typed.height) < 0.01)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        let cleared = try rect()
        #expect(inputRect().minY == typedInput.minY && inputRect().height == typedInput.height)
        #expect(abs(cleared.minY - typed.minY) < 0.01)
        #expect(abs(cleared.height - typed.height) < 0.01)
    }
}
