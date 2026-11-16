import AppKit
import Testing
@testable import Editor

@MainActor
private func namedPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("floating-notes-tests-\(UUID().uuidString)"))
}

@MainActor
@Suite struct CopySelectionTests {
    @Test func copyingAWordDoesNotDragTheListMarkerAlong() throws {
        let h = try EditorHarness("- alpha beta\n- gamma")
        let board = namedPasteboard()
        defer { board.releaseGlobally() }
        h.caret(at: 2)
        h.press(NSResponder.shiftRight, times: 5)
        #expect(h.controller.copySelection(to: board))
        #expect(board.string(forType: .string) == "alpha")
        #expect(board.string(forType: .html) == "<meta charset=\"utf-8\"><p>alpha</p>")
        #expect(board.string(forType: .floatingNotesMarkdown) == "alpha")
    }

    @Test func shiftDownCopyHasNoPhantomItem() throws {
        let h = try EditorHarness("- alpha\n- gamma\n- delta")
        let board = namedPasteboard()
        defer { board.releaseGlobally() }
        h.caret(at: 2)
        h.press(NSResponder.shiftDown)
        #expect(h.editor.selectedRange == NSRange(location: 2, length: 8))
        #expect(h.controller.copySelection(to: board))
        #expect(board.string(forType: .string) == "- alpha")
        #expect(board.string(forType: .html) == "<meta charset=\"utf-8\"><ul><li>alpha</li></ul>")
        #expect(board.string(forType: .floatingNotesMarkdown) == "- alpha")
    }
}

@MainActor
@Suite struct LinkSchemeTests {
    /// 첫 줄 첫 링크의 글자 한가운데(텍스트 뷰 좌표).
    private func linkPoint(_ h: EditorHarness) throws -> CGPoint {
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        let location = try #require(h.controller.contentStorage.location(h.controller.contentStorage.documentRange.location, offsetBy: 0))
        let fragment = try #require(h.controller.layoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment)
        let span = try #require(h.document.lines[0].spans.first)
        let rect = try #require(fragment.rects(for: span.contentRange).first)
        let origin = h.view.textContainerOrigin
        let frame = fragment.layoutFragmentFrame
        return CGPoint(x: origin.x + frame.minX + rect.midX, y: origin.y + frame.minY + rect.midY)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "x-app://open?a=1", "data:text/html,hi", "../relative"])
    func otherSchemesAreNotOpenedOnClick(address: String) throws {
        let h = try EditorHarness("[문서](\(address)) 끝\n")
        h.caret(atEndOfLine: 1)
        var opened: [URL] = []
        h.editor.onOpenLink = { opened.append($0) }
        let point = try linkPoint(h)
        // 누를 수 있는 것으로 치지 않는다. 눌러도 열지 않고 보통 글자처럼 커서만 간다.
        #expect(!h.controller.isInteractive(at: point))
        #expect(h.controller.hit(at: point) == nil)
        #expect(!h.controller.handleMouseDown(at: point))
        #expect(opened.isEmpty)
    }

    @Test(arguments: ["https://a.example/x", "http://a.example", "mailto:a@b.example"])
    func webAndMailLinksOpen(address: String) throws {
        let h = try EditorHarness("[문서](\(address)) 끝\n")
        h.caret(atEndOfLine: 1)
        var opened: [URL] = []
        h.editor.onOpenLink = { opened.append($0) }
        let point = try linkPoint(h)
        #expect(h.controller.isInteractive(at: point))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(opened == [URL(string: address)!])
    }
}

@MainActor
@Suite struct CompositionCallbackTests {
    @Test func composingSyllableIsReportedBeforeItIsCommitted() throws {
        let h = try EditorHarness()
        h.type("안")
        h.mark("ㄴ")
        #expect(h.view.hasMarkedText())
        #expect(h.changes == ["안", "안ㄴ"])
        h.mark("녀")
        h.mark("녕")
        #expect(h.editor.text == "안녕")
        // 조합 중에도 그때그때의 원문을 알린다(자동 저장이 마지막 글자를 빠뜨리지 않는다).
        #expect(h.changes == ["안", "안ㄴ", "안녀", "안녕"])
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 1, length: 1))
        h.commit("녕")
        #expect(!h.view.hasMarkedText())
        #expect(h.changes.last == "안녕")
        #expect(h.editor.text == "안녕")
    }

    @Test func heightFollowsAComposingSyllableThatWraps() throws {
        let h = try EditorHarness()
        // 한 줄을 꽉 채운다: 한 글자만 더 들어가면 줄이 넘어간다.
        var filled = ""
        let oneLine = h.editor.contentHeight
        while h.editor.contentHeight == oneLine {
            filled += "가"
            h.editor.text = filled
        }
        let twoLines = h.editor.contentHeight
        h.editor.text = String(filled.dropLast())
        #expect(h.editor.contentHeight == oneLine)
        h.caret(at: h.document.length)
        let reported = h.heights.count

        h.mark("ㄱ")
        #expect(h.view.hasMarkedText())
        #expect(h.heights.count == reported + 1)
        #expect(h.heights.last == twoLines)
        // 조합을 지우면 다시 줄어든다.
        h.mark("")
        #expect(h.heights.last == oneLine)
    }

    @Test func restylingStillLeavesTheCompositionAlone() throws {
        let h = try EditorHarness("- ")
        h.caret(atEndOfLine: 0)
        h.mark("ㅎ")
        h.mark("하")
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 2, length: 1))
        h.commit("하")
        #expect(h.editor.text == "- 하")
        // 조합마다 한 번, 확정에 한 번.
        #expect(h.changes == ["- ㅎ", "- 하", "- 하"])
        while h.editor.undoManager.canUndo { h.undo() }
        #expect(h.editor.text == "- ")
    }

    @Test func editsThatPostNoNotificationAreFlushedOnTheNextMainQueueTurn() async throws {
        let h = try EditorHarness("가")
        let storage = try #require(h.view.textStorage)
        // `textDidChange`도 `setMarkedText`도 거치지 않는 변경.
        storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "나")
        #expect(h.changes.isEmpty)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(h.changes == ["가나"])
    }
}

@MainActor
@Suite struct ForwardDeleteTests {
    @Test func forwardDeleteAtLineEndSwallowsTheNextLineMarker() throws {
        let h = try EditorHarness("- a\n- b\n[ ] c")
        h.caret(at: 3)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "- ab\n[ ] c")
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 0))
        h.caret(at: 4)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "- abc")
        h.undo()
        #expect(h.editor.text == "- ab\n[ ] c")
    }

    @Test func forwardDeleteSwallowsIndentationButKeepsVisibleSyntax() throws {
        let h = try EditorHarness("가\n\t\t나\n# 제목")
        h.caret(at: 1)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "가나\n# 제목")
        // 제목의 `#`은 편집 중에 보이는 글자라 그대로 이어 붙는다.
        h.caret(at: 2)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "가나# 제목")
        // 줄 가운데에서는 보통의 지우기다.
        h.caret(at: 0)
        h.press(NSResponder.forwardDelete)
        #expect(h.editor.text == "나# 제목")
    }
}

@MainActor
@Suite struct LineEndingTests {
    @Test func textIsNormalizedToLineFeeds() throws {
        let h = try EditorHarness("a\r\nb\rc\u{2028}d\u{2029}e\r\n")
        #expect(h.editor.text == "a\nb\nc\nd\ne\n")
        #expect(h.view.string == "a\nb\nc\nd\ne\n")
        #expect(h.document.lines.count == 6)
        #expect(h.changes.isEmpty)
        // 같은 글을 다른 줄바꿈으로 다시 넣어도 아무 일도 없다(커서, 되돌리기 기록 유지).
        h.caret(at: 1)
        h.type("!")
        h.editor.text = "a!\r\nb\r\nc\r\nd\r\ne\r\n"
        #expect(h.editor.undoManager.canUndo)
        #expect(h.editor.selectedRange == NSRange(location: 2, length: 0))
        #expect(h.changes == ["a!\nb\nc\nd\ne\n"])
    }

    @Test func caretCannotSitInsideALineBreak() throws {
        let h = try EditorHarness("- a\r\n- b")
        // `\r\n`이 한 글자가 되었으므로 그 사이가 없다.
        h.caret(at: 4)
        #expect(h.editor.selectedRange == NSRange(location: 6, length: 0))
        h.press(NSResponder.newline)
        h.perform(.moveLineUp)
        #expect(!h.editor.text.contains("\r"))
        #expect(h.editor.text == "- a\n- b\n- ")
    }

    @Test func pasteIsNormalized() throws {
        let board = namedPasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("- 하나\r\n- 둘\r셋\u{2028}넷\u{2029}끝", forType: .string)
        let h = try EditorHarness("앞")
        h.caret(at: 1)
        h.step { h.controller.paste(from: board) }
        #expect(h.editor.text == "앞- 하나\n- 둘\n셋\n넷\n끝")
        #expect(h.changes == ["앞- 하나\n- 둘\n셋\n넷\n끝"])
        h.undo()
        #expect(h.editor.text == "앞")
    }

    @Test func insertedTextFromOtherPathsIsNormalizedToo() throws {
        // 끌어다 놓기, 서비스 메뉴처럼 `insertText`로 들어오는 글.
        let h = try EditorHarness("앞")
        h.caret(at: 1)
        h.step { h.view.insertText("가\r\n나", replacementRange: h.view.selectedRange()) }
        #expect(h.editor.text == "앞가\n나")
        #expect(h.editor.selectedRange == NSRange(location: 4, length: 0))
        h.undo()
        #expect(h.editor.text == "앞")
    }

    @Test(arguments: ["insertLineBreak:", "insertParagraphSeparator:", "insertNewlineIgnoringFieldEditor:", "insertNewline:"])
    func everyReturnVariantInsertsALineFeedAndContinuesTheList(selector: String) throws {
        let h = try EditorHarness("- 하나")
        h.caret(atEndOfLine: 0)
        h.press(Selector(selector))
        h.type("둘")
        #expect(h.editor.text == "- 하나\n- 둘")
        #expect(h.document.lines.map(\.kind) == [.bullet, .bullet])
    }
}

@MainActor
@Suite struct BracketTriggerTests {
    @Test func typingAnOpeningBracketBeforeAClosingOneDoesNotMakeATodo() throws {
        let h = try EditorHarness("] a")
        h.caret(at: 0)
        h.type("[")
        #expect(h.editor.text == "[] a")
        #expect(h.document.lines[0].kind == .paragraph)
        // 커서가 제자리에 있어 다음 글자가 대괄호 안에 들어간다.
        #expect(h.editor.selectedRange == NSRange(location: 1, length: 0))
        h.type("q")
        #expect(h.editor.text == "[q] a")
    }

    @Test func spaceAfterEmptyBracketsStillMakesATodo() throws {
        let h = try EditorHarness()
        h.type("[] 할 일")
        #expect(h.editor.text == "[ ] 할 일")
        #expect(h.document.lines[0].kind == .todo(done: false))
        let nested = try EditorHarness()
        nested.type("- [] 표준")
        #expect(nested.editor.text == "- [ ] 표준")
        #expect(nested.document.lines[0].kind == .todo(done: false))
    }
}

@MainActor
@Suite struct TrailingCodeLineTests {
    /// 마지막 문단 조각(문서 끝의 빈 줄은 이 조각에 붙은 빈 줄 조각이다).
    private func lastFragment(_ h: EditorHarness) throws -> MarkdownLayoutFragment {
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        var last: NSTextLayoutFragment?
        h.controller.layoutManager.enumerateTextLayoutFragments(
            from: h.controller.layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            last = fragment
            return true
        }
        return try #require(last as? MarkdownLayoutFragment)
    }

    private func storageKeys(_ h: EditorHarness) throws -> Set<NSAttributedString.Key> {
        let storage = try #require(h.view.textStorage)
        var keys = Set<NSAttributedString.Key>()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
            keys.formUnion(attributes.keys)
        }
        return keys
    }

    @Test func emptyLastLineOfAnUnterminatedCodeBlockIsStyledAsCode() throws {
        let h = try EditorHarness()
        h.type("```")
        h.press(NSResponder.newline)
        // 닫는 줄을 지워 닫히지 않은 블록으로 만든다: "```\ncode\n"
        h.type("code")
        h.editor.selectedRange = NSRange(location: 8, length: 4)
        h.press(NSResponder.backspace)
        h.press(NSResponder.newline)
        #expect(h.editor.text == "```\ncode\n")
        #expect(h.document.lines.map(\.kind) == [.fenceOpen, .code, .code])
        #expect(h.editor.selectedRange == NSRange(location: 9, length: 0))

        let fragment = try lastFragment(h)
        let lines = fragment.textLineFragments
        #expect(lines.count == 2)
        let code = try #require(lines.first)
        let empty = try #require(lines.last)
        #expect(empty.characterRange.length == 0)
        // 빈 줄도 코드 줄의 높이와 들여쓰기를 갖는다(커서가 코드 글자와 같은 자리에 선다).
        #expect(empty.typographicBounds.height == EditorMetrics.codeLineHeight)
        let frame = fragment.layoutFragmentFrame
        #expect(frame.minX + empty.typographicBounds.minX == EditorMetrics.codeBlockPadX)
        #expect(frame.minX + empty.typographicBounds.minX == frame.minX + code.typographicBounds.minX)
        // 코드 상자가 빈 줄까지 덮고 거기서 아래 모서리를 닫는다.
        let decoration = try #require(fragment.decoration)
        #expect(decoration.codeBox?.bottom == true)
        let box = try #require(fragment.codeBoxRect)
        #expect(box.maxY == empty.typographicBounds.maxY)
        #expect(box.minY == code.typographicBounds.minY)
        // 원문 저장소에는 여전히 기본 글꼴과 글자색만 있다.
        #expect(try storageKeys(h) == [.font, .foregroundColor])

        // 커서가 다른 줄에 갔다 와도 같다.
        h.caret(at: 0)
        let away = try #require(try lastFragment(h).textLineFragments.last)
        #expect(away.characterRange.length == 0)
        #expect(try lastFragment(h).layoutFragmentFrame.minX + away.typographicBounds.minX == EditorMetrics.codeBlockPadX)
        #expect(try lastFragment(h).codeBoxRect?.maxY == away.typographicBounds.maxY)
        h.caret(at: h.document.length)
        let back = try #require(try lastFragment(h).textLineFragments.last)
        #expect(back.typographicBounds.height == EditorMetrics.codeLineHeight)
        #expect(try lastFragment(h).layoutFragmentFrame.minX + back.typographicBounds.minX == EditorMetrics.codeBlockPadX)

        // 그 줄에 글자를 치면 보통의 코드 문단이 되고, 저장소에는 여전히 서식이 없다.
        h.type("x")
        #expect(h.document.lines[2].kind == .code)
        #expect(try storageKeys(h) == [.font, .foregroundColor])
        let typed = try lastFragment(h)
        #expect(typed.textLineFragments.count == 1)
        #expect(typed.decoration?.codeBox?.bottom == true)
    }

    @Test func composingOnTheEmptyLastCodeLineKeepsTheComposition() throws {
        let h = try EditorHarness("```\ncode\n")
        h.caret(at: h.document.length)
        h.mark("ㅎ")
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 9, length: 1))
        h.mark("하")
        h.mark("한")
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == NSRange(location: 9, length: 1))
        #expect(h.editor.text == "```\ncode\n한")
        // 조합을 지우면 다시 빈 코드 줄이 된다.
        h.mark("")
        #expect(h.editor.text == "```\ncode\n")
        h.mark("ㄱ")
        #expect(h.view.hasMarkedText())
        h.commit("ㄱ")
        #expect(!h.view.hasMarkedText())
        #expect(h.editor.text == "```\ncode\nㄱ")
        #expect(try storageKeys(h).subtracting([.font, .foregroundColor]).isEmpty)
    }

    @Test func emptyLastLineOutsideACodeBlockIsUnchanged() throws {
        let h = try EditorHarness("```\ncode\n```\n")
        h.caret(at: h.document.length)
        let closed = try lastFragment(h)
        let empty = try #require(closed.textLineFragments.last)
        #expect(empty.characterRange.length == 0)
        #expect(closed.layoutFragmentFrame.minX + empty.typographicBounds.minX == 0)
        let box = try #require(closed.codeBoxRect)
        // 닫힌 블록의 상자는 닫는 줄에서 끝난다.
        #expect(box.maxY <= empty.typographicBounds.minY)

        // 닫는 줄을 지우면 빈 줄이 코드가 되고, 다시 닫으면 돌아온다.
        h.editor.selectedRange = NSRange(location: 9, length: 3)
        h.press(NSResponder.backspace)
        #expect(h.document.lines.last?.kind == .code)
        let open = try lastFragment(h)
        #expect(open.codeBoxRect?.maxY == open.textLineFragments.last?.typographicBounds.maxY)
        h.undo()
        let again = try lastFragment(h)
        #expect(try #require(again.codeBoxRect).maxY <= (try #require(again.textLineFragments.last)).typographicBounds.minY)
    }
}
