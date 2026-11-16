import AppKit
import Testing
@testable import Editor

// 기호를 보이지 않는 편집(D-036)의 나머지: 한글 조합, 링크, 코드 블록, 인라인 코드 상자의 자리.

private typealias Key = EditorShortcuts.Key

@MainActor
@Suite struct CompositionSafetyTests {
    @Test(arguments: ["#", "##", "###", "-", "[]", ">"])
    func blockTriggerNeverFiresMidComposition(trigger: String) throws {
        let h = try EditorHarness()
        h.type(trigger)
        h.mark("ㅎ")
        #expect(h.view.hasMarkedText())
        #expect(h.editor.text == trigger + "ㅎ")
        // 조합 중에 들어오는 공백(입력기가 조합 글자를 바꿔 넣는 경로)은 그대로 지나간다.
        #expect(h.controller.textView(h.view, shouldChangeTextIn: h.view.markedRange(), replacementString: " "))
        h.mark("하")
        h.commit("한")
        #expect(!h.view.hasMarkedText())
        // 두벌식은 Space를 누르면 조합을 확정한 뒤 공백을 넣는다. 기호 뒤에 글자가 있으므로 바뀌지 않는다.
        h.type(" ")
        #expect(h.marked == trigger + "한 |")
        #expect(h.document.lines[0].kind == .paragraph)
        // 조합이 끝난 글 앞(줄 맨 앞)에 기호를 치면 바뀐다. 되돌리고 다시 해도 같다.
        h.editor.text = "한글"
        h.caret(at: 0)
        h.type(trigger)
        h.type(" ")
        let converted = h.editor.text
        #expect(converted.hasSuffix(" 한글"))
        #expect(h.document.lines[0].kind != .paragraph)
        h.undo()
        #expect(h.editor.text == trigger + "한글")
        h.redo()
        #expect(h.editor.text == converted)
    }

    @Test func codeBlockTriggerNeverFiresMidComposition() throws {
        let h = try EditorHarness()
        h.type("``")
        h.mark("ㅎ")
        #expect(h.editor.text == "``ㅎ")
        #expect(h.controller.textView(h.view, shouldChangeTextIn: h.view.markedRange(), replacementString: "`"))
        h.commit("한")
        h.type("`")
        #expect(h.editor.text == "``한`")
        #expect(h.document.lines[0].kind == .paragraph)
        // 만든 블록 안에서 조합해도 블록은 그대로다.
        let k = try EditorHarness()
        k.type("```")
        k.mark("ㅎ")
        k.mark("하")
        #expect(k.view.hasMarkedText())
        #expect(k.editor.text == "```\n하\n```")
        k.commit("한")
        #expect(k.marked == "```\n한|\n```")
        // 조합의 단계들을 되돌리면 빈 블록으로 돌아간다.
        for _ in 0..<3 where k.editor.text != "```\n\n```" { k.undo() }
        #expect(k.editor.text == "```\n\n```")
    }

    @Test func closingMarkerAfterAComposedSyllableConverts() throws {
        let h = try EditorHarness()
        h.type("**")
        h.mark("ㄱ")
        h.mark("구")
        h.mark("굵")
        #expect(h.editor.text == "**굵")
        // 조합 중에는 모양을 다시 입혀도 조합이 풀리지 않는다.
        h.controller.restyleAll()
        #expect(h.view.hasMarkedText())
        h.commit("굵")
        h.type("*")
        #expect(h.document.lines[0].spans.isEmpty)
        h.type("*")
        #expect(h.marked == "**굵**|")
        #expect(h.document.lines[0].spans.first?.kind == .bold)
        // 되돌리면 친 기호가 글자 그대로 남는다(백슬래시로 막는다).
        h.undo()
        #expect(h.editor.text == "\\*\\*굵\\*\\*")
        #expect(h.document.lines[0].markedSpans.isEmpty)
        h.redo()
        #expect(h.document.lines[0].spans.first?.kind == .bold)
    }

    @Test func typingAttributeIsAppliedBeforeTheCompositionStarts() throws {
        let h = try EditorHarness("가 ")
        h.caret(atEndOfLine: 0)
        h.key(Key.b, "ㅠ", .command)
        h.mark("ㄱ")
        // 기호 쌍을 먼저 넣고 그 사이에서 조합한다. 조합 중에는 원문을 따로 고치지 않는다.
        #expect(h.view.hasMarkedText())
        #expect(h.editor.text == "가 **ㄱ**")
        #expect(h.view.markedRange() == NSRange(location: 4, length: 1))
        h.mark("구")
        h.mark("굵")
        #expect(h.view.markedRange() == NSRange(location: 4, length: 1))
        h.commit("굵")
        #expect(h.marked == "가 **굵|**")
        h.mark("ㄱ")
        h.commit("게")
        #expect(h.marked == "가 **굵게|**")
        #expect(h.document.lines[0].spans.first?.kind == .bold)
    }

    @Test func cancelledCompositionLeavesNoEmptyMarkers() throws {
        let h = try EditorHarness("가 ")
        h.caret(atEndOfLine: 0)
        h.key(Key.h, "ㅗ", [.command, .shift])
        h.mark("ㅎ")
        #expect(h.editor.text == "가 ==ㅎ==")
        // 조합하던 글자를 지우면(⌫) 조합이 글자 없이 끝난다. 넣어 둔 기호 쌍도 사라진다.
        h.mark("")
        #expect(!h.view.hasMarkedText())
        #expect(h.marked == "가 |")
    }

    @Test func composingOverASelectionFollowsTheSameRulesAsTyping() throws {
        // 구간의 글자를 모두 고르고 조합하면 서식을 잇는다.
        let h = try EditorHarness("가**나다**라")
        h.place(at: 3, length: 2)
        h.mark("ㅎ")
        #expect(h.view.hasMarkedText())
        #expect(h.editor.text == "가**ㅎ**라")
        h.commit("한")
        #expect(h.marked == "가**한|**라")
        // 여는 기호만 든 선택: 기호를 남기고 먼저 지운 뒤 그 앞에서 조합한다.
        let k = try EditorHarness("가나**다라**")
        k.place(at: 1, length: 4)
        k.mark("ㅎ")
        #expect(k.view.hasMarkedText())
        #expect(k.editor.text == "가ㅎ**라**")
        k.commit("한")
        #expect(k.marked == "가한|**라**")
    }

    @Test func arrowsAndShortcutsAreLeftAloneWhileComposingNextToMarkers() throws {
        let h = try EditorHarness("**굵게**")
        h.place(at: 4)
        h.mark("ㅎ")
        #expect(h.editor.text == "**굵게ㅎ**")
        let marked = h.view.markedRange()
        h.key(Key.b, "ㅠ", .command)
        h.step { h.editor.perform(.link) }
        #expect(h.view.hasMarkedText())
        #expect(h.view.markedRange() == marked)
        #expect(h.controller.linkSession == nil)
        let asked = NSRange(location: 7, length: 0)
        #expect(h.controller.textView(h.view, willChangeSelectionFromCharacterRange: h.view.selectedRange(), toCharacterRange: asked) == asked)
        h.commit("한")
        #expect(h.marked == "**굵게한|**")
    }
}

@MainActor
@Suite struct LinkEditingTests {
    private func commit(_ h: EditorHarness, _ address: String) {
        h.controller.linkField.address = address
        h.step {
            _ = h.controller.linkField.control(
                h.controller.linkField.input, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))
            )
        }
    }

    @Test func shortcutOnASelectionAsksForTheAddressThenMakesTheLink() throws {
        let h = try EditorHarness("문서 보기")
        h.window.layoutIfNeeded()
        h.place(at: 0, length: 2)
        #expect(h.key(Key.l, "l", .command))
        // 원문은 아직 그대로이고, 고른 글자 아래에 주소 칸이 떠서 포커스를 받는다.
        #expect(h.editor.text == "문서 보기")
        let field = h.controller.linkField
        #expect(!field.isHidden)
        #expect(field.address.isEmpty)
        #expect(h.window.firstResponder !== h.view)
        let anchor = try #require(h.controller.segmentRects(for: NSRange(location: 0, length: 2)).last)
        #expect(field.frame.minY >= anchor.maxY)
        #expect(field.frame.height == h.theme.component(.controlHeight))
        #expect(field.frame.width <= h.theme.component(.linkFieldWidth))
        #expect(field.frame.maxX <= h.view.bounds.maxX)
        // 칸이 잘리지 않게 내용 높이에 든다.
        #expect(h.editor.contentHeight >= field.frame.maxY)

        commit(h, "https://a.example/doc")
        #expect(h.marked == "[문서|](https://a.example/doc) 보기")
        #expect(field.isHidden)
        #expect(h.window.firstResponder === h.view)
        let padding = h.theme.docPadding
        #expect(h.editor.contentHeight == padding.top + padding.bottom + h.theme.lineHeight(.body))
        // 글자만 보이고 링크 모양이다.
        let span = try #require(h.document.lines[0].spans.first)
        #expect(span.kind == .link("https://a.example/doc"))
        #expect(try h.fontSize(line: 0, at: span.closeMarker).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
        let shown = try h.display(line: 0).attributes(at: 1, effectiveRange: nil)
        #expect(shown[.markdownLink] as? String == "https://a.example/doc")
        #expect(shown[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        h.undo()
        #expect(h.editor.text == "문서 보기")
        h.redo()
        #expect(h.editor.text == "[문서](https://a.example/doc) 보기")
    }

    @Test func shortcutInsideALinkEditsOrRemovesTheAddress() throws {
        let h = try EditorHarness("앞 [문서](https://a.example) 뒤")
        h.place(at: 4)
        #expect(h.key(Key.l, "l", .command))
        #expect(h.controller.linkField.address == "https://a.example")
        commit(h, "https://b.example/x y")
        #expect(h.marked == "앞 [문서|](https://b.example/x%20y) 뒤")
        h.undo()
        #expect(h.editor.text == "앞 [문서](https://a.example) 뒤")
        // 주소를 비우면 링크를 벗기고 글자만 남긴다.
        h.place(at: 4)
        h.key(Key.l, "l", .command)
        commit(h, "")
        #expect(h.marked == "앞 문서| 뒤")
        h.undo()
        #expect(h.editor.text == "앞 [문서](https://a.example) 뒤")
    }

    @Test func escapeOrLosingFocusCancels() throws {
        let h = try EditorHarness("문서 보기")
        h.place(at: 0, length: 2)
        h.key(Key.l, "l", .command)
        h.controller.linkField.address = "https://a.example"
        _ = h.controller.linkField.control(
            h.controller.linkField.input, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )
        #expect(h.editor.text == "문서 보기")
        #expect(h.controller.linkField.isHidden)
        #expect(h.window.firstResponder === h.view)
        #expect(h.editor.selectedRange == NSRange(location: 0, length: 2))
        // 다른 곳으로 포커스가 가도 그만둔다.
        h.key(Key.l, "l", .command)
        #expect(!h.controller.linkField.isHidden)
        h.window.makeFirstResponder(h.view)
        #expect(h.controller.linkField.isHidden)
        #expect(h.controller.linkSession == nil)
        #expect(h.editor.text == "문서 보기")
        #expect(!h.editor.undoManager.canUndo)
    }

    @Test func nothingHappensWithoutATarget() throws {
        let h = try EditorHarness("문서\n```\ncode\n```")
        h.place(at: 1)
        h.key(Key.l, "l", .command)
        #expect(h.controller.linkSession == nil)
        #expect(h.controller.linkField.isHidden)
        h.place(at: h.document.lines[2].start, length: 2)
        h.key(Key.l, "l", .command)
        #expect(h.controller.linkSession == nil)
    }

    @Test func editingTheLinkTextEditsTheVisibleText() throws {
        let h = try EditorHarness("[문서](https://a.example) 뒤")
        // 줄 맨 앞의 링크: 커서는 링크 글자 안에서 시작한다.
        h.press(NSResponder.end)
        h.press(NSResponder.home)
        #expect(h.marked == "[|문서](https://a.example) 뒤")
        h.press(NSResponder.right)
        h.type("헌")
        #expect(h.marked == "[문헌|서](https://a.example) 뒤")
        h.press(NSResponder.right)
        h.press(NSResponder.backspace)
        #expect(h.marked == "[문헌|](https://a.example) 뒤")
        // 링크 끝에서 →: 링크 밖으로 나간다. 이어 치는 글은 링크가 아니다.
        h.press(NSResponder.right)
        h.type("!")
        #expect(h.marked == "[문헌](https://a.example)!| 뒤")
        // 링크의 글자를 모두 지우면 주소도 함께 사라진다.
        h.press(NSResponder.left)
        h.press(NSResponder.backspace, times: 2)
        #expect(h.marked == "|! 뒤")
    }

    @Test func textChangeFromOutsideWhileTheFieldIsOpenDropsTheSession() throws {
        let h = try EditorHarness("문서 보기")
        h.place(at: 0, length: 2)
        h.key(Key.l, "l", .command)
        h.editor.text = "다른 글"
        #expect(h.controller.linkSession == nil)
        #expect(h.controller.linkField.isHidden)
        #expect(h.editor.text == "다른 글")
    }
}

@MainActor
@Suite struct CodeBlockEditingTests {
    @Test func enterTypeAndLeaveWithReturnOnTheEmptyLastLine() throws {
        let h = try EditorHarness("앞")
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.newline)
        h.type("```")
        h.press(NSResponder.newline)
        #expect(h.marked == "앞\n```\n|\n```")
        h.type("let a = 1")
        h.press(NSResponder.newline)
        h.type("let b = 2")
        h.press(NSResponder.newline)
        #expect(h.marked == "앞\n```\nlet a = 1\nlet b = 2\n|\n```")
        // 빈 마지막 줄에서 Return: 그 줄이 지워지고 블록 아래에 문단이 열린다.
        h.press(NSResponder.newline)
        #expect(h.marked == "앞\n```\nlet a = 1\nlet b = 2\n```\n|")
        h.type("뒤")
        #expect(h.document.lines.map(\.kind) == [.paragraph, .fenceOpen, .code, .code, .fenceClose, .paragraph])
        h.undo()
        h.undo()
        #expect(h.editor.text == "앞\n```\nlet a = 1\nlet b = 2\n\n```")
        h.redo()
        #expect(h.editor.text == "앞\n```\nlet a = 1\nlet b = 2\n```\n")
    }

    @Test func arrowsPassThroughTheBlockWithoutStoppingOnFenceLines() throws {
        let h = try EditorHarness("앞\n```swift\nlet a\nlet b\n```\n뒤")
        let lines = h.document.lines
        h.window.layoutIfNeeded()
        h.caret(atEndOfLine: 0)
        var seen: [Int] = []
        for _ in 0..<4 {
            h.press(NSResponder.down)
            seen.append(h.document.lineIndex(at: h.editor.selectedRange.location))
        }
        #expect(seen == [2, 3, 5, 5])
        seen = []
        for _ in 0..<4 {
            h.press(NSResponder.up)
            seen.append(h.document.lineIndex(at: h.editor.selectedRange.location))
        }
        #expect(seen == [3, 2, 0, 0])
        // ←→ 로도 ``` 줄을 건너뛴다.
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.right)
        #expect(h.editor.selectedRange.location == lines[2].start)
        h.press(NSResponder.left)
        #expect(h.editor.selectedRange.location == lines[0].end)
        h.caret(at: lines[3].end)
        h.press(NSResponder.right)
        #expect(h.editor.selectedRange.location == lines[5].start)
        h.press(NSResponder.left)
        #expect(h.editor.selectedRange.location == lines[3].end)
        #expect(h.editor.text == "앞\n```swift\nlet a\nlet b\n```\n뒤")
    }

    @Test func downArrowFromTheLastLineMakesAParagraphWhenTheDocumentEndsThere() throws {
        let h = try EditorHarness("```\na\nb\n```")
        h.window.layoutIfNeeded()
        h.place(at: 4)
        h.press(NSResponder.down)
        #expect(h.marked == "```\na\nb|\n```" || h.marked == "```\na\n|b\n```")
        h.place(at: 7)
        h.press(NSResponder.down)
        #expect(h.marked == "```\na\nb\n```\n|")
        h.undo()
        #expect(h.editor.text == "```\na\nb\n```")
        h.redo()
        // 이제 아래에 줄이 있으므로 다시 내려가도 줄이 더 생기지 않는다.
        h.place(at: 7)
        h.view.doCommand(by: NSResponder.down)
        #expect(h.marked == "```\na\nb\n```\n|")
        h.undo()
        #expect(h.editor.text == "```\na\nb\n```")
        // 문서 맨 앞의 블록에서 ↑: 위에 문단을 만든다.
        h.place(at: 4)
        h.press(NSResponder.up)
        #expect(h.marked == "|\n```\na\nb\n```")
    }

    @Test func languageTagIsKeptInTheSourceAndNeverShown() throws {
        let h = try EditorHarness("```swift\nlet a\n```")
        h.place(at: h.document.lines[1].end)
        h.type(" = 1")
        h.press(NSResponder.newline)
        h.type("x")
        #expect(h.editor.text == "```swift\nlet a = 1\nx\n```")
        #expect(try h.fontSize(line: 0, at: h.document.lines[0].range).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
        #expect(h.controller.codeText(in: 0...3) == "let a = 1\nx")
    }

    /// ``` 줄은 보이지 않으므로 어떤 키로도 한쪽만 지워지지 않는다: 블록이 그대로 있거나 통째로 사라진다.
    @Test func noKeyDeletesOnlyOneFence() throws {
        let source = "앞 글\n```swift\nlet a\n\nlet b\n```\n뒤 글"
        let selectors = [
            "deleteBackward:", "deleteForward:", "deleteWordBackward:", "deleteWordForward:",
            "deleteToBeginningOfLine:", "deleteToEndOfLine:", "deleteToBeginningOfParagraph:", "deleteToEndOfParagraph:",
        ]
        let length = (source as NSString).length
        for selector in selectors {
            for location in 0...length {
                for extent in [0, 3, 9] where location + extent <= length {
                    let h = try EditorHarness(source)
                    h.editor.selectedRange = NSRange(location: location, length: extent)
                    h.press(NSSelectorFromString(selector))
                    let text = h.editor.text
                    let kinds = h.document.lines.map(\.kind)
                    let intact = text.contains("```swift\n") && kinds.filter { $0 == .fenceOpen }.count == 1
                        && kinds.filter { $0 == .fenceClose }.count == 1
                    #expect(intact || !text.contains("`"), "\(selector) @\(location)+\(extent): \(text.debugDescription)")
                }
            }
        }
    }

    /// 모두 선택은 블록뿐인 문서에서도 ``` 줄까지 고른다. ⌫ 한 번으로 문서가 빈다.
    @Test func selectAllInADocumentThatIsOnlyABlockSelectsTheFencesToo() throws {
        let h = try EditorHarness("```\na\nb\n```")
        h.place(at: 4)
        h.view.selectAll(nil)
        #expect(h.marked == "|```\na\nb\n```|")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|")
        h.undo()
        #expect(h.editor.text == "```\na\nb\n```")
    }

    @Test func typingOverASelectionThatLeavesTheBlockReplacesTheWholeBlock() throws {
        let h = try EditorHarness("앞\n```\na\nb\n```\n뒤")
        let lines = h.document.lines
        // 윗줄 가운데에서 블록 안까지 끌어 고른다: 블록이 통째로 선택에 든다.
        h.editor.selectedRange = NSRange(location: 0, length: lines[2].end)
        #expect(h.marked == "|앞\n```\na\nb\n```\n|뒤")
        h.type("x")
        #expect(h.marked == "x|뒤")
        h.undo()
        #expect(h.editor.text == "앞\n```\na\nb\n```\n뒤")
    }
}

@MainActor
@Suite struct InlineBoxGeometryTests {
    /// 그 줄의 첫 줄 조각과 문단 조각.
    private func fragment(_ h: EditorHarness, line: Int) throws -> (MarkdownLayoutFragment, NSTextLineFragment) {
        h.window.layoutIfNeeded()
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        let location = try #require(h.controller.contentStorage.location(
            h.controller.contentStorage.documentRange.location, offsetBy: h.document.lines[line].start
        ))
        let fragment = try #require(h.controller.layoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment)
        return (fragment, try #require(fragment.textLineFragments.first))
    }

    /// 상자의 왼쪽 여백과 오른쪽 여백(글자의 실제 자리에서 잰다).
    private func paddings(_ h: EditorHarness, key: NSAttributedString.Key) throws -> (left: CGFloat, right: CGFloat, box: InlineBackground) {
        let (fragment, line) = try fragment(h, line: 0)
        let span = try #require(h.document.lines[0].markedSpans.first)
        let shown = try h.display(line: 0)
        let box = try #require(shown.attribute(key, at: span.contentRange.location, effectiveRange: nil) as? InlineBackground)
        let rect = try #require(fragment.rects(for: span.contentRange).first)
        let boxLeft = rect.minX + box.leadShift - box.padX
        let boxRight = rect.maxX + box.padX
        // 첫 글자의 실제 왼쪽 끝: 둘째 글자의 자리에서 첫 글자의 너비를 뺀다(감춘 기호 뒤의 자간에 흔들리지 않는다).
        let first = shown.attributedSubstring(from: NSRange(location: span.contentRange.location, length: 1))
        let glyphLeft = line.typographicBounds.minX
            + line.locationForCharacter(at: span.contentRange.location + 1).x - first.size().width
        let glyphRight = line.typographicBounds.minX + line.locationForCharacter(at: NSMaxRange(span.contentRange)).x
        return (glyphLeft - boxLeft, boxRight - glyphRight, box)
    }

    @Test func inlineCodeBoxHasEqualPaddingOnBothSides() throws {
        let h = try EditorHarness("가 `code` 나")
        let measured = try paddings(h, key: .markdownCodeBox)
        let pad = h.theme.component(.codePaddingX)
        #expect(abs(measured.left - pad) < 0.25, "왼쪽 \(measured.left)")
        #expect(abs(measured.right - pad) < 0.25, "오른쪽 \(measured.right)")
    }

    @Test func highlightBoxHasEqualPaddingOnBothSides() throws {
        let h = try EditorHarness("가 ==형광== 나")
        let measured = try paddings(h, key: .markdownHighlight)
        #expect(abs(measured.left - EditorMetrics.highlightPadX) < 0.25, "왼쪽 \(measured.left)")
        #expect(abs(measured.right - EditorMetrics.highlightPadX) < 0.25, "오른쪽 \(measured.right)")
    }

    @Test func copyButtonSitsInsideTheBlockCorner() throws {
        let h = try EditorHarness("앞\n```swift\nlet a = 1\nlet b = 2\n```\n뒤")
        let (open, _) = try fragment(h, line: 1)
        let point = try #require(h.controller.textPoint(forLine: 2))
        _ = h.controller.handleMouseMoved(at: point)
        #expect(h.controller.hoveredCodeBlock == 1...4)
        let origin = h.view.textContainerOrigin
        let box = try #require(open.codeBoxRect)
        let top = origin.y + open.layoutFragmentFrame.minY + box.minY
        let right = origin.x + h.controller.textContainer.size.width
        let button = h.controller.copyButton.frame
        // 버튼은 상자 안, 오른쪽 위 모서리에서 같은 만큼 들어와 있고 둥근 모서리에 걸리지 않는다.
        #expect(button.minY - top == EditorMetrics.copyButtonInset)
        #expect(right - button.maxX == EditorMetrics.copyButtonInset)
        #expect(button.width == h.theme.component(.iconButton))
        let radius = h.theme.shape(.codeBlockRadius)
        let corner = CGPoint(x: right - radius, y: top + radius)
        let farthest = CGPoint(x: button.maxX, y: button.minY)
        #expect(hypot(farthest.x - corner.x, farthest.y - corner.y) <= radius)
    }
}
