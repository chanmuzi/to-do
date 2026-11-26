import AppKit
import Testing
@testable import Editor

// 기호를 보이지 않는 편집(D-036)을 실제 입력 경로로 확인한다: 글자는 `insertText`, 키는 `doCommand(by:)`,
// 단축키는 `performKeyEquivalent`, 한글 조합은 `setMarkedText`. 단계마다 원문과 커서를 함께 견준다
// (`|`가 커서, 둘이면 그 사이가 선택).

private typealias Key = EditorShortcuts.Key

@MainActor
@Suite struct BlockTriggerTypingTests {
    @Test(arguments: [
        ("#", "# |"), ("##", "## |"), ("###", "### |"), ("-", "- |"), ("[]", "[ ] |"), (">", "+ |"),
    ])
    func triggerOnAnEmptyLineConvertsAndUndoRestoresTheTypedCharacters(trigger: String, result: String) throws {
        let h = try EditorHarness()
        h.type(trigger)
        #expect(h.marked == trigger + "|")
        h.type(" ")
        #expect(h.marked == result)
        h.type("글")
        #expect(h.marked == result.replacingOccurrences(of: "|", with: "글|"))
        // 되돌리면 글자, 그다음 바꾼 것이 풀려 친 기호가 보통 글자로 남는다.
        h.undo()
        #expect(h.marked == result)
        h.undo()
        #expect(h.marked == trigger + "|")
        h.redo()
        #expect(h.marked == result)
    }

    @Test(arguments: [
        ("#", "# |본문 글"), ("##", "## |본문 글"), ("###", "### |본문 글"),
        ("-", "- |본문 글"), ("[]", "[ ] |본문 글"), (">", "+ |본문 글"),
    ])
    func triggerOnALineWithTextConvertsIt(trigger: String, result: String) throws {
        let h = try EditorHarness("앞\n본문 글\n뒤")
        h.caret(at: 2)
        h.type(trigger)
        #expect(h.marked == "앞\n\(trigger)|본문 글\n뒤")
        h.type(" ")
        #expect(h.marked == "앞\n\(result)\n뒤")
        h.undo()
        #expect(h.marked == "앞\n\(trigger)|본문 글\n뒤")
        h.redo()
        #expect(h.marked == "앞\n\(result)\n뒤")
    }

    @Test func triggersConvertBetweenEveryBlockType() throws {
        let h = try EditorHarness("# 제목")
        h.caret(at: 0)
        // 제목의 `#`은 보이지 않는다. 줄 맨 앞으로 가면 커서는 글자 앞에 선다.
        #expect(h.marked == "# |제목")
        let steps: [(typed: String, result: String)] = [
            ("-", "- |제목"), ("##", "## |제목"), ("[]", "[ ] |제목"), (">", "+ |제목"),
            ("###", "+ ### |제목"), ("-", "- |제목"), ("[]", "- [ ] |제목"), ("#", "# |제목"),
        ]
        var previous = h.marked
        for step in steps {
            h.type(step.typed)
            let typed = previous.replacingOccurrences(of: "|", with: step.typed + "|")
            #expect(h.marked == typed)
            h.type(" ")
            #expect(h.marked == step.result)
            h.undo()
            #expect(h.marked == typed)
            h.redo()
            #expect(h.marked == step.result)
            previous = step.result
        }
    }

    @Test func conversionKeepsIndentationAndFoldsFollow() throws {
        let h = try EditorHarness("- 부모\n\t- 항목\n+ 토글\n\t안")
        h.editor.foldedLines = [2]
        h.caret(at: h.document.lines[1].contentStart)
        h.type("[]")
        h.type(" ")
        #expect(h.editor.text == "- 부모\n\t- [ ] 항목\n+ 토글\n\t안")
        #expect(h.editor.foldedLines == [2])
        // 접힌 토글을 다른 종류로 바꾸면 접힘이 풀려 감춘 줄이 드러난다. 되돌리면 접힘도 돌아온다.
        h.caret(at: h.document.lines[2].contentStart)
        h.type("-")
        h.type(" ")
        #expect(h.editor.text == "- 부모\n\t- [ ] 항목\n- 토글\n\t안")
        #expect(h.editor.foldedLines.isEmpty)
        h.undo()
        #expect(h.editor.text == "- 부모\n\t- [ ] 항목\n+ -토글\n\t안")
        #expect(h.editor.foldedLines == [2])
    }

    @Test func aTriggerLeavesTheSameTypeAndTheMiddleOfALineAlone() throws {
        let h = try EditorHarness("- 항목")
        h.caret(at: 2)
        h.type("- ")
        #expect(h.marked == "- - |항목")
        h.caret(atEndOfLine: 0)
        h.type(" # ")
        #expect(h.marked == "- - 항목 # |")
    }

    @Test func thirdBacktickMakesACodeBlockAndSwallowsTheHabitualReturnOrSpace() throws {
        for follow in ["return", "space", "none"] {
            let h = try EditorHarness()
            h.type("``")
            #expect(h.marked == "``|")
            h.type("`")
            #expect(h.marked == "```\n|\n```")
            switch follow {
            case "return": h.press(NSResponder.newline)
            case "space": h.type(" ")
            default: break
            }
            #expect(h.marked == "```\n|\n```")
            h.type("let x = 1")
            #expect(h.marked == "```\nlet x = 1|\n```")
            // 삼킨 뒤의 Return, Space는 보통대로 들어간다.
            h.type(" ")
            h.press(NSResponder.newline)
            #expect(h.marked == "```\nlet x = 1 \n|\n```")
        }
    }

    @Test func thirdBacktickOnALineWithTextWrapsThatLineAndUndoRestoresIt() throws {
        let h = try EditorHarness("앞\n- 항목\n뒤")
        h.caret(at: h.document.lines[1].contentStart)
        h.type("``")
        #expect(h.marked == "앞\n- ``|항목\n뒤")
        h.type("`")
        #expect(h.marked == "앞\n```\n|항목\n```\n뒤")
        #expect(h.document.lines.map(\.kind) == [.paragraph, .fenceOpen, .code, .fenceClose, .paragraph])
        // 되돌리면 친 백틱 둘이 보통 글자로 남는다.
        h.undo()
        #expect(h.editor.text == "앞\n- ``항목\n뒤")
        #expect(h.document.lines.map(\.kind) == [.paragraph, .bullet, .paragraph])
        h.redo()
        #expect(h.editor.text == "앞\n```\n항목\n```\n뒤")
    }

    @Test func backticksAwayFromTheLineStartStayInlineCode() throws {
        let h = try EditorHarness()
        h.type("글 ```")
        #expect(h.marked == "글 ```|")
        #expect(h.document.lines[0].kind == .paragraph)
    }
}

@MainActor
@Suite struct BlockBackspaceTypingTests {
    @Test(arguments: ["# 제목", "## 제목", "### 제목", "- 제목", "[ ] 제목", "[x] 제목", "- [ ] 제목", "+ 제목"])
    func backspaceAtTheVisualStartMakesAParagraphThenJoins(line: String) throws {
        let h = try EditorHarness("앞\n" + line)
        h.caret(at: 2)
        #expect(h.marked == "앞\n" + line.replacingOccurrences(of: "제목", with: "|제목"))
        h.press(NSResponder.backspace)
        #expect(h.marked == "앞\n|제목")
        h.press(NSResponder.backspace)
        #expect(h.marked == "앞|제목")
        h.undo()
        #expect(h.editor.text == "앞\n제목")
        h.undo()
        #expect(h.editor.text == "앞\n" + line)
    }

    @Test func nestedItemLosesItsMarkerThenOutdentsThenJoins() throws {
        let h = try EditorHarness("- 부모\n\t\t- 항목")
        h.caret(atEndOfLine: 1)
        h.press(NSResponder.home)
        var seen: [String] = []
        for _ in 0..<4 {
            h.press(NSResponder.backspace)
            seen.append(h.marked)
        }
        #expect(seen == ["- 부모\n\t\t|항목", "- 부모\n\t|항목", "- 부모\n|항목", "- 부모|항목"])
    }

    @Test func emptyCodeBlockIsRemovedByBackspaceAndOthersAreKept() throws {
        let h = try EditorHarness()
        h.type("```")
        #expect(h.marked == "```\n|\n```")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|")
        h.undo()
        #expect(h.marked == "```\n|\n```")
        // 글이 있는 블록의 첫 줄 맨 앞에서는 블록을 푼다(``` 줄이 지워지고 글은 남는다).
        h.type("x")
        h.press(NSResponder.home)
        h.press(NSResponder.backspace)
        #expect(h.marked == "|x")
        h.undo()
        #expect(h.editor.text == "```\nx\n```")
    }
}

@MainActor
@Suite struct InlineTypingTests {
    @Test(arguments: [
        ("**굵게**", InlineSpan.Kind.bold), ("~~취소~~", .strike), ("==형광==", .highlight(1)), ("`코드`", .code),
    ])
    func typingTheClosingMarkerConvertsOnTheSpot(source: String, kind: InlineSpan.Kind) throws {
        let h = try EditorHarness()
        h.type("앞 ")
        let unfinished = String(source.dropLast())
        h.type(unfinished)
        // 닫는 기호를 다 치기 전에는 친 글자가 그대로 보인다.
        #expect(h.document.lines[0].spans.isEmpty)
        #expect(try h.fontSize(line: 0, at: NSRange(location: 2, length: 1)).allSatisfy { $0 > 1 })
        h.type(String(source.last!))
        #expect(h.marked == "앞 \(source)|")
        let span = try #require(h.document.lines[0].spans.first)
        #expect(span.kind == kind)
        // 그 자리에서 기호가 사라진다. 커서가 그 줄에 있어도 보이지 않는다.
        #expect(try h.fontSize(line: 0, at: span.openMarker).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
        #expect(try h.fontSize(line: 0, at: span.closeMarker).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
        // 닫는 기호 뒤에 이어 치는 글자는 서식이 없다.
        h.type(" 뒤")
        #expect(h.marked == "앞 \(source) 뒤|")
        #expect(h.document.lines[0].spans == [span])
        // 되돌리면 한 글자씩 풀린다. 서식이 된 것을 되돌리면 친 기호가 글자 그대로 남는다
        // (원문에서는 백슬래시로 막아 두어 다시 서식이 되지 않는다).
        h.undo()
        h.undo()
        h.undo()
        let literal = EditorCommands.escaped(source)
        #expect(h.marked == "앞 \(literal)|")
        #expect(h.document.lines[0].markedSpans.isEmpty)
        #expect(h.document.lines[0].escapes.count == literal.count - source.count)
        // 한 번 더 되돌리면 마지막에 친 글자가 지워진다.
        h.undo()
        #expect(h.marked == "앞 \(unfinished)|")
        #expect(h.document.lines[0].spans.isEmpty)
        h.redo()
        h.redo()
        #expect(h.document.lines[0].spans == [span])
    }

    @Test func highlightColorSuffixIsHiddenWithTheMarker() throws {
        let h = try EditorHarness()
        h.type("==형광=={3}")
        let span = try #require(h.document.lines[0].spans.first)
        #expect(span.kind == .highlight(3))
        #expect(try h.fontSize(line: 0, at: span.closeMarker).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
    }

    @Test func typingAtTheEndOfARunContinuesTheFormat() throws {
        let h = try EditorHarness("가 **굵게** 나")
        // 구간 뒤의 글자를 지나 왼쪽으로 오면 구간의 끝(안쪽)에 선다.
        h.caret(atEndOfLine: 0)
        h.press(NSResponder.left, times: 2)
        #expect(h.marked == "가 **굵게|** 나")
        h.type("더")
        #expect(h.marked == "가 **굵게더|** 나")
        // 줄 끝의 구간에서도 End는 구간의 끝(안쪽)이다.
        let end = try EditorHarness("가 **굵게**")
        end.press(NSResponder.end)
        #expect(end.marked == "가 **굵게|**")
        end.type("더")
        #expect(end.marked == "가 **굵게더|**")
    }

    @Test func rightArrowPastTheEndOfARunMakesTheNextTextPlain() throws {
        let h = try EditorHarness("가 **굵게**")
        h.press(NSResponder.end)
        h.press(NSResponder.right)
        // 자리는 그대로이고 원문 위치만 구간 밖이다.
        #expect(h.marked == "가 **굵게**|")
        h.type("나")
        #expect(h.marked == "가 **굵게**나|")
        #expect(h.document.lines[0].spans.count == 1)
        #expect(h.document.lines[0].spans[0].contentRange == NSRange(location: 4, length: 2))
    }

    @Test func typingBeforeARunIsPlainExceptAtTheStartOfTheLine() throws {
        let h = try EditorHarness("가 **굵게** 나")
        h.caret(at: 0)
        h.press(NSResponder.right, times: 2)
        #expect(h.marked == "가 |**굵게** 나")
        h.type("x")
        #expect(h.marked == "가 x|**굵게** 나")
        // 줄이 구간으로 시작하면 줄 맨 앞의 커서는 구간 안이다.
        let lead = try EditorHarness("**굵게** 나")
        lead.press(NSResponder.end)
        lead.press(NSResponder.home)
        #expect(lead.marked == "**|굵게** 나")
        lead.type("x")
        #expect(lead.marked == "**x|굵게** 나")
        // ←를 한 번 누르면 같은 자리에서 구간 밖으로 나간다.
        lead.press(NSResponder.home)
        lead.press(NSResponder.left)
        #expect(lead.marked == "|**x굵게** 나")
        lead.type("y")
        #expect(lead.marked == "y|**x굵게** 나")
    }
}

@MainActor
@Suite struct TypingAttributeTests {
    @Test func boldShortcutWithACaretFormatsWhatIsTypedNext() throws {
        let h = try EditorHarness("가 ")
        h.caret(atEndOfLine: 0)
        #expect(h.key(Key.b, "b", .command))
        // 첫 입력 전에는 원문 변경이나 실행 취소 단계가 생기지 않는다.
        #expect(h.marked == "가 |")
        #expect(h.changes.isEmpty && !h.editor.undoManager.canUndo)
        #expect(h.editor.formattingState.bold)
        h.type("굵")
        #expect(h.marked == "가 **굵|**")
        h.type("게")
        #expect(h.marked == "가 **굵게|**")
        // 다시 눌러 끄면 커서가 구간 밖으로 나가고, 이어 치는 글자는 서식이 없다.
        #expect(h.key(Key.b, "b", .command))
        #expect(h.marked == "가 **굵게**|")
        h.type(" 나")
        #expect(h.marked == "가 **굵게** 나|")
        // 첫 글자와 기호를 함께 되돌리고 다시 한다.
        for _ in 0..<3 { h.undo() }
        #expect(h.editor.text == "가 **굵**")
        h.undo()
        #expect(h.marked == "가 |")
        #expect(!h.editor.undoManager.canUndo)
        h.redo()
        #expect(h.editor.text == "가 **굵**")
        for _ in 0..<3 { h.redo() }
        #expect(h.editor.text == "가 **굵게** 나")
    }

    @Test func boldCommitsMarkedTextAndFormatsOnlySubsequentInput() throws {
        let h = try EditorHarness()
        h.mark("가")
        #expect(h.key(Key.b, "ㅠ", .command))
        #expect(!h.view.hasMarkedText() && h.editor.text == "가")
        #expect(h.editor.formattingState.bold)
        h.mark("나")
        h.commit("나 ")
        #expect(h.editor.text == "가**나** ")
        #expect(h.editor.formattingState.bold)
        #expect(h.key(Key.b, "ㅠ", .command))
        #expect(!h.editor.formattingState.bold)
        h.type("다")
        #expect(h.editor.text == "가**나** 다")
    }

    @Test func toolbarListCommandsDescribeTheEditedLines() throws {
        let h = try EditorHarness("하나\n둘")
        h.editor.selectedRange = NSRange(location: 0, length: h.editor.text.utf16.count)
        h.editor.perform(.toggleBullet)
        #expect(h.editor.text == "- 하나\n- 둘")
        #expect(h.editor.formattingState.bullet)
        h.editor.perform(.toggleTodo)
        #expect(h.editor.formattingState.checklist && !h.editor.formattingState.bullet)
        h.editor.perform(.toggleTodo)
        #expect(h.editor.text == "하나\n둘")
    }

    @Test func formattingStateCombinesCursorAndPendingMarks() throws {
        let h = try EditorHarness.at("**~~가|나~~**")
        #expect(h.editor.formattingState.bold && h.editor.formattingState.strikethrough)
        h.perform(.strikethrough)
        #expect(h.editor.formattingState.bold && !h.editor.formattingState.strikethrough)
        h.place(at: 0)
        #expect(!h.editor.formattingState.bold && !h.editor.formattingState.strikethrough)
    }

    @Test func eachShortcutTogglesItsOwnTypingAttribute() throws {
        let h = try EditorHarness()
        #expect(h.key(Key.x, "X", [.command, .shift]))
        h.type("취소")
        #expect(h.marked == "~~취소|~~")
        #expect(h.key(Key.x, "X", [.command, .shift]))
        h.type(" ")
        #expect(h.key(Key.e, "e", .command))
        h.type("code")
        #expect(h.marked == "~~취소~~ `code|`")
        #expect(h.key(Key.e, "e", .command))
        h.type(" ")
        // ⇧⌘H는 마지막 색(처음은 노랑 바탕)을 켜고, 다시 누르면 끈다(D-008 대체).
        #expect(h.key(Key.h, "H", [.command, .shift]))
        h.type("색")
        #expect(h.marked == "~~취소~~ `code` ==색|=={노랑}")
        #expect(h.key(Key.h, "H", [.command, .shift]))
        h.type("밖")
        #expect(h.marked == "~~취소~~ `code` ==색=={노랑}밖|")
    }

    @Test func togglingTwiceOrMovingAwayCancelsThePendingFormat() throws {
        let h = try EditorHarness("가나")
        h.caret(atEndOfLine: 0)
        h.key(Key.b, "b", .command)
        h.key(Key.b, "b", .command)
        h.type("x")
        #expect(h.marked == "가나x|")
        h.key(Key.b, "b", .command)
        h.press(NSResponder.left)
        h.press(NSResponder.right)
        h.type("y")
        #expect(h.marked == "가나xy|")
    }

    @Test func togglingOffInTheMiddleOfARunSplitsItAroundTheTypedText() throws {
        let h = try EditorHarness("**가나**")
        h.place(at: 3)
        h.key(Key.b, "b", .command)
        #expect(h.marked == "**가|나**")
        h.type("x")
        #expect(h.marked == "**가**x|**나**")
        h.undo()
        #expect(h.marked == "**가|나**")
    }

    @Test func shortcutsOnASelectionFormatItAndCycleTheHighlight() throws {
        let h = try EditorHarness("가 나다 라")
        h.place(at: 2, length: 2)
        h.key(Key.b, "b", .command)
        #expect(h.marked == "가 **|나다|** 라")
        h.key(Key.x, "X", [.command, .shift])
        #expect(h.marked == "가 **~~|나다|~~** 라")
        var seen: [String] = []
        // ⇧⌘H는 마지막 색을 걸고, 이미 그 색이면 벗긴다.
        for _ in 0..<4 {
            h.key(Key.h, "H", [.command, .shift])
            seen.append(h.editor.text)
        }
        #expect(seen == [
            "가 **~~==나다=={노랑}~~** 라", "가 **~~나다~~** 라", "가 **~~==나다=={노랑}~~** 라", "가 **~~나다~~** 라",
        ])
        // 굵게를 벗길 때 안쪽 구간(취소선)은 기호째로 남는다.
        h.key(Key.b, "b", .command)
        #expect(h.marked == "가 |~~나다~~| 라")
        h.undo()
        #expect(h.editor.text == "가 **~~나다~~** 라")
    }
}

@MainActor
@Suite struct HiddenMarkerMovementTests {
    // a0 b1 c2 *3 *4 d5 e6 f7 *8 *9 g10 h11 i12
    private func harness() throws -> EditorHarness { try EditorHarness("가나다**라마바**사아자") }

    @Test func arrowsNeverStopInsideAMarker() throws {
        let h = try harness()
        h.place(at: 0)
        var right: [Int] = []
        for _ in 0..<11 {
            h.press(NSResponder.right)
            right.append(h.editor.selectedRange.location)
        }
        // 구간의 끝(8)에서 한 번은 제자리에서 구간 밖(10)으로 나간다.
        #expect(right == [1, 2, 3, 6, 7, 8, 10, 11, 12, 13, 13])
        var left: [Int] = []
        for _ in 0..<10 {
            h.press(NSResponder.left)
            left.append(h.editor.selectedRange.location)
        }
        #expect(left == [12, 11, 8, 7, 6, 3, 2, 1, 0, 0])
        let line = h.document.lines[0]
        #expect((right + left).allSatisfy { line.marker(enclosing: $0) == nil })
    }

    @Test func shiftArrowsSelectVisibleCharactersOnly() throws {
        let h = try harness()
        h.place(at: 2)
        var seen: [String] = []
        for _ in 0..<5 {
            h.press(NSResponder.shiftRight)
            seen.append(h.marked)
        }
        #expect(seen == ["가나|다|**라마바**사아자", "가나|다**라|마바**사아자", "가나|다**라마|바**사아자", "가나|다**라마바|**사아자", "가나|다**라마바**사|아자"])
        seen = []
        for _ in 0..<5 {
            h.press(NSResponder.shiftLeft)
            seen.append(h.marked)
        }
        #expect(seen == ["가나|다**라마바|**사아자", "가나|다**라마|바**사아자", "가나|다**라|마바**사아자", "가나|다|**라마바**사아자", "가나|다**라마바**사아자"])
        h.place(at: 11)
        seen = []
        for _ in 0..<5 {
            h.press(NSResponder.shiftLeft)
            seen.append(h.marked)
        }
        #expect(seen == ["가나다**라마바**|사|아자", "가나다**라마|바**사|아자", "가나다**라|마바**사|아자", "가나다**|라마바**사|아자", "가나|다**라마바**사|아자"])
    }

    @Test func wordAndLineMovementLandOnValidPositions() throws {
        let h = try EditorHarness("가나 **다라** 마바\n[링크 글](https://a.example/x) 끝")
        let selectors = [
            NSResponder.wordRight, NSResponder.wordRight, NSResponder.wordRight, NSResponder.down, NSResponder.wordLeft,
            NSResponder.wordLeft, NSResponder.home, NSResponder.end, NSResponder.up, NSResponder.home,
            #selector(NSResponder.moveWordRightAndModifySelection(_:)), #selector(NSResponder.moveWordRightAndModifySelection(_:)),
            #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)),
        ]
        h.place(at: 0)
        for selector in selectors {
            h.press(selector)
            let selection = h.editor.selectedRange
            for position in [selection.location, NSMaxRange(selection)] {
                let line = h.document.line(at: position)
                #expect(line.marker(enclosing: position) == nil, "\(selector) → \(h.marked)")
            }
            #expect(h.editor.text == "가나 **다라** 마바\n[링크 글](https://a.example/x) 끝")
        }
    }

    @Test func clickAndDragLandOnTheVisibleText() throws {
        let h = try EditorHarness("가나다**라마바**사아자 그리고 [링크](https://a.example) 끝")
        h.window.layoutIfNeeded()
        func point(_ location: Int) throws -> CGPoint {
            let rect = try #require(h.controller.segmentRects(for: NSRange(location: location, length: 0)).first)
            return CGPoint(x: rect.minX, y: rect.midY)
        }
        // 구간 끝과 앞의 경계를 누른다: 끝은 안쪽, 앞은 바깥쪽.
        h.view.setSelectedRange(NSRange(location: h.view.characterIndexForInsertion(at: try point(8)), length: 0))
        #expect(h.editor.selectedRange == NSRange(location: 8, length: 0))
        h.view.setSelectedRange(NSRange(location: h.view.characterIndexForInsertion(at: try point(5)), length: 0))
        #expect(h.editor.selectedRange == NSRange(location: 3, length: 0))
        // 끌어서 고른다: b 앞에서 e 뒤까지, 그리고 e 뒤에서 h 뒤까지.
        let from = h.view.characterIndexForInsertion(at: try point(1))
        let to = h.view.characterIndexForInsertion(at: try point(7))
        h.view.setSelectedRange(NSRange(location: from, length: to - from))
        #expect(h.marked == "가|나다**라마|바**사아자 그리고 [링크](https://a.example) 끝")
        let later = h.view.characterIndexForInsertion(at: try point(12))
        h.view.setSelectedRange(NSRange(location: to, length: later - to))
        #expect(h.marked == "가나다**라마|바**사아|자 그리고 [링크](https://a.example) 끝")
    }

    @Test func caretIsAFullLineTallNextToHiddenMarkers() throws {
        let h = try harness()
        h.window.layoutIfNeeded()
        let line = h.theme.lineHeight(.body)
        for location in [3, 5, 8, 10] {
            let rect = try #require(h.controller.segmentRects(for: NSRange(location: location, length: 0)).first)
            #expect(rect.height == line)
        }
        // 기호의 양쪽은 같은 자리다.
        let before = try #require(h.controller.segmentRects(for: NSRange(location: 8, length: 0)).first)
        let after = try #require(h.controller.segmentRects(for: NSRange(location: 10, length: 0)).first)
        #expect(abs(before.minX - after.minX) < 0.1)
    }
}

@MainActor
@Suite struct RunBoundaryDeletionTests {
    @Test func backspaceOverARunBoundaryDeletesAVisibleCharacter() throws {
        let h = try EditorHarness("가**나다**라")
        h.place(at: 7)
        #expect(h.marked == "가**나다**|라")
        h.press(NSResponder.backspace)
        #expect(h.marked == "가**나|**라")
        h.undo()
        #expect(h.editor.text == "가**나다**라")
        h.place(at: 3)
        #expect(h.marked == "가**|나다**라")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|**나다**라")
        h.undo()
        h.place(at: 1)
        h.press(NSResponder.forwardDelete)
        #expect(h.marked == "가|**다**라")
    }

    @Test func deletingTheLastVisibleCharacterRemovesTheMarkers() throws {
        let h = try EditorHarness("가**나다**라")
        h.place(at: 5)
        h.press(NSResponder.backspace)
        #expect(h.marked == "가**나|**라")
        h.press(NSResponder.backspace)
        #expect(h.marked == "가|라")
        h.undo()
        #expect(h.editor.text == "가**나**라")
        h.redo()
        #expect(h.marked == "가|라")
    }

    @Test func deletingOrReplacingASelectionNeverLeavesOrphanMarkers() throws {
        let cases: [(text: String, selection: NSRange, typed: String?, result: String)] = [
            ("가**나다**라", NSRange(location: 3, length: 2), nil, "가|라"),
            ("가**나다**라", NSRange(location: 3, length: 2), "x", "가**x|**라"),
            ("가**나다**라", NSRange(location: 0, length: 4), nil, "|**다**라"),
            ("가**나다**라", NSRange(location: 4, length: 4), "x", "가**나**x|"),
            ("**가나** ~~다라~~", NSRange(location: 3, length: 7), nil, "**가**|~~라~~"),
            // 지운 뒤에 줄 맨 앞에 남는 공백은 함께 지운다(남겨 두면 감춘 들여쓰기가 된다).
            ("[글자](https://a.example) 뒤", NSRange(location: 1, length: 2), nil, "|뒤"),
            ("==형광=={2}", NSRange(location: 2, length: 2), nil, "|"),
        ]
        for item in cases {
            let h = try EditorHarness(item.text)
            h.place(at: item.selection.location, length: item.selection.length)
            if let typed = item.typed { h.type(typed) } else { h.press(NSResponder.backspace) }
            #expect(h.marked == item.result, "\(item.text)")
            h.undo()
            #expect(h.editor.text == item.text)
        }
    }

    @Test func cutPasteAndWordDeleteKeepTheSourceWellFormed() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("local.floating-notes.tests.notion-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let h = try EditorHarness("가 **나다** 라")
        // 구간의 글자만 골라 복사해도 서식이 함께 나간다.
        h.place(at: 4, length: 2)
        #expect(h.controller.copySelection(to: board))
        #expect(board.string(forType: .string) == "**나다**")
        h.place(at: 5, length: 1)
        #expect(h.controller.copySelection(to: board))
        #expect(board.string(forType: .string) == "**다**")
        // 붙여 넣은 Markdown은 그대로 원문에 들어가고 기호는 감춰진다.
        h.caret(atEndOfLine: 0)
        h.step { h.controller.paste(from: board) }
        #expect(h.editor.text == "가 **나다** 라**다**")
        #expect(h.document.lines[0].spans.count == 2)
        let pasted = h.document.lines[0].spans[1]
        #expect(try h.fontSize(line: 0, at: pasted.openMarker).allSatisfy { $0 == EditorMetrics.hiddenFontSize })
        // 낱말 지우기가 지나간 뒤에도 빈 기호 쌍이나 짝 잃은 기호가 남지 않는다.
        for _ in 0..<6 {
            h.press(#selector(NSResponder.deleteWordBackward(_:)))
            let text = h.editor.text
            let visible = h.document.lines[0].markedSpans.reduce(text) { partial, _ in partial }
            #expect(!visible.contains("****"))
            let stars = text.components(separatedBy: "**").count - 1
            #expect(stars == h.document.lines[0].markedSpans.count * 2, "\(text)")
        }
        #expect(h.editor.text.isEmpty)
    }
}
