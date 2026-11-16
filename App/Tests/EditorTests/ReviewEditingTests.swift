import AppKit
import Testing
@testable import Editor

/// 리뷰에서 재현된 편집 문제들. 모두 실제 입력 경로로 넣고 원문을 견준다.
@MainActor
@Suite struct ReviewEditingTests {
    typealias Key = EditorShortcuts.Key

    // MARK: 그 자리에서 바뀐 서식을 되돌리기

    @Test func undoRightAfterAConversionKeepsTheTypedCharactersLiteral() throws {
        let h = try EditorHarness()
        h.type("가 ==나==")
        #expect(h.marked == "가 ==나==|")
        #expect(h.document.lines[0].spans.map(\.kind) == [.highlight(1)])
        h.undo()
        // 친 글자가 그대로 보이고(백슬래시는 감춘다), 이어 쳐도 다시 서식이 되지 않는다.
        #expect(h.marked == "가 \\=\\=나\\=\\=|")
        #expect(h.document.lines[0].markedSpans.isEmpty)
        h.type(" 다")
        #expect(h.editor.text == "가 \\=\\=나\\=\\= 다")
        #expect(h.document.lines[0].markedSpans.isEmpty)
        // 링크도 같다.
        let k = try EditorHarness()
        k.type("[글](https://a.example)")
        #expect(k.document.lines[0].markedSpans.count == 1)
        k.undo()
        #expect(k.editor.text == "\\[글\\](https://a.example)")
        #expect(k.document.lines[0].markedSpans.isEmpty)
    }

    // MARK: 3. 조합이 글자 없이 끝남

    @Test func cancellingACompositionOverAFullySelectedRunRemovesTheEmptyMarkers() throws {
        let h = try EditorHarness.at("x **|ab|** y")
        h.mark("ㅎ")
        #expect(h.editor.text == "x **ㅎ** y")
        // 입력기에서 ⌫: 조합 중인 글자가 비고 조합이 끝난다.
        h.mark("")
        h.step { h.view.unmarkText() }
        #expect(h.marked == "x | y")
        // 글자를 확정하면 서식이 남는다.
        let k = try EditorHarness.at("x **|ab|** y")
        k.mark("ㅎ")
        k.commit("하")
        #expect(k.marked == "x **하|** y")
    }

    // MARK: 4. 정해 둔 서식

    @Test func pendingFormatWrapsEachPastedLine() throws {
        let h = try EditorHarness.at("a|")
        h.key(Key.b, "b", .command)
        h.paste("1\n2")
        #expect(h.editor.text == "a**1**\n**2**")
        #expect(h.document.lines.map { $0.spans.map(\.kind) } == [[.bold], [.bold]])
        // 구간 안에서 다른 서식을 켜고 여러 줄을 붙여도 기호가 줄을 넘지 않는다.
        let k = try EditorHarness.at("==가|나==")
        k.key(Key.b, "b", .command)
        k.paste("1\n2")
        #expect(k.editor.text == "==가==**1**\n**2**==나==")
    }

    @Test func blockTriggerDropsThePendingFormat() throws {
        let h = try EditorHarness()
        h.key(Key.b, "b", .command)
        h.type("#")
        #expect(h.editor.text == "**#**")
        h.type(" ")
        #expect(h.marked == "# |")
        h.type("제목")
        #expect(h.editor.text == "# 제목")
    }

    @Test func spaceAtTheEndOfARunStaysOutsideUntilTheNextCharacter() throws {
        let h = try EditorHarness()
        h.key(Key.b, "b", .command)
        h.type("가")
        #expect(h.marked == "**가|**")
        h.type(" ")
        // 닫는 기호 앞은 공백일 수 없다. 공백은 기호 밖에 놓이고 기호는 감춘 채로 있다.
        #expect(h.marked == "**가** |")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        h.type("나")
        #expect(h.marked == "**가 나|**")
        // 한글 조합으로 이어 써도 같다.
        h.type(" ")
        h.mark("ㄷ")
        h.commit("다")
        #expect(h.marked == "**가 나 다|**")
        // 공백 뒤에 커서를 옮기면 이어지지 않는다.
        h.type(" ")
        h.press(NSResponder.left)
        h.press(NSResponder.right, times: 2)
        h.type("라")
        #expect(h.editor.text == "**가 나 다** 라")
    }

    @Test func deletingUpToASpaceInsideARunMovesTheSpaceOut() throws {
        let h = try EditorHarness.at("**가 나|** 끝")
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "**가**  끝")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
    }

    // MARK: 5. 감춘 줄 머리가 든 선택

    @Test func selectionFromTheLineStartKeepsTheBlockType() throws {
        let h = try EditorHarness.at("- ab|c")
        h.press(#selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)))
        h.type("X")
        #expect(h.marked == "- X|c")
        let k = try EditorHarness.at("- [ ] ab|c")
        k.press(#selector(NSResponder.deleteToBeginningOfLine(_:)))
        #expect(k.marked == "- [ ] |c")
    }

    @Test func joiningLinesNeverExposesAHiddenPrefix() throws {
        let h = try EditorHarness.at("ab|c\n- item")
        h.press(#selector(NSResponder.moveToEndOfLineAndModifySelection(_:)))
        h.press(NSResponder.shiftRight)
        h.press(NSResponder.backspace)
        #expect(h.marked == "ab|item")
        let k = try EditorHarness.at("a|\n# 제목")
        k.press(NSResponder.shiftRight)
        k.press(NSResponder.forwardDelete)
        #expect(k.marked == "a|제목")
        // 줄을 통째로 고른 것(줄 맨 앞부터 다음 줄 맨 앞까지)은 그 줄만 지운다.
        let whole = try EditorHarness("a\n- b\n- c")
        whole.place(at: 2, length: 4)
        whole.press(NSResponder.backspace)
        #expect(whole.marked == "a\n- |c")
    }

    // MARK: 8. 같은 서식 안에 붙여넣기

    @Test func pastingFormattedSourceInsideTheSameFormatStripsItsMarkers() throws {
        let bold = try EditorHarness.at("**a|b**")
        bold.paste("**은 글**")
        #expect(bold.editor.text == "**a은 글b**")
        let highlight = try EditorHarness.at("==a|b=={2}")
        highlight.paste("==h==")
        #expect(highlight.editor.text == "==ahb=={2}")
        #expect(highlight.document.lines[0].spans.map(\.kind) == [.highlight(2)])
        let code = try EditorHarness.at("`a|b`")
        code.paste("`c`")
        #expect(code.editor.text == "`acb`")
        let link = try EditorHarness.at("[글|자](https://a.example)")
        link.paste("[다른](https://b.example)")
        #expect(link.editor.text == "[글다른자](https://a.example)")
        // 다른 서식은 그대로 들어간다.
        let other = try EditorHarness.at("**가|나**")
        other.paste("~~c~~")
        #expect(other.editor.text == "**가~~c~~나**")
        // 영문자 사이에 붙어 기호로 읽히지 않을 서식은 기호를 벗겨 글자만 넣는다(기호가 글자로 드러나지 않는다).
        let glued = try EditorHarness.at("a|b")
        glued.paste("**굵은 글**")
        #expect(glued.editor.text == "a굵은 글b")
    }

    // MARK: 작은 것들

    @Test func transposeNeverBreaksAMarkerPair() throws {
        let h = try EditorHarness("**ab**")
        h.place(at: 4)
        h.press(#selector(NSResponder.transpose(_:)))
        #expect(h.editor.text == "**ba**")
        // 기호를 사이에 둔 두 글자는 바꾸지 않는다.
        let k = try EditorHarness("가**나**")
        k.place(at: 1)
        k.press(#selector(NSResponder.transpose(_:)))
        #expect(k.editor.text == "가**나**")
        let plain = try EditorHarness.at("가|나")
        plain.press(#selector(NSResponder.transpose(_:)))
        #expect(plain.marked == "나가|")
    }

    @Test func closingBracketTypedInLinkTextIsEscaped() throws {
        let h = try EditorHarness.at("[글|자](https://a.example) 뒤")
        h.type("]")
        #expect(h.editor.text == "[글\\]자](https://a.example) 뒤")
        #expect(h.document.lines[0].markedSpans.map(\.kind) == [.link("https://a.example")])
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "[글자](https://a.example) 뒤")
    }

    @Test func linkCoversExactlyTheSelectedText() throws {
        let h = try EditorHarness.at("**a|b** c|d")
        #expect(h.key(Key.l, "l", .command))
        h.step { h.controller.commitLink("https://a.example") }
        #expect(h.editor.text == "**a**[**b** c](https://a.example)d")
        #expect(h.document.lines[0].markedSpans.map(\.kind) == [.bold, .link("https://a.example"), .bold])
    }

    @Test func leadingSpaceLeftByADeletionIsRemoved() throws {
        let h = try EditorHarness.at("**y|** x")
        h.press(NSResponder.backspace)
        #expect(h.marked == "|x")
        #expect(h.document.lines[0].indentLength == 0)
    }

    @Test func adjacentRunsOfTheSameKindAreMerged() throws {
        let h = try EditorHarness.at("**ab** |**cd**")
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "**abcd**")
        h.undo()
        #expect(h.editor.text == "**ab** **cd**")
        // 다른 서식끼리는 합치지 않는다.
        let k = try EditorHarness.at("**ab** |~~cd~~")
        k.press(NSResponder.backspace)
        #expect(k.editor.text == "**ab**~~cd~~")
    }

    @Test func caretAfterRedoOfALineJoinIsWhereTheEditLeftIt() throws {
        let h = try EditorHarness.at("**y**\n|**게**")
        h.press(NSResponder.backspace)
        let joined = h.marked
        h.undo()
        #expect(h.marked == "**y**\n|**게**")
        h.redo()
        #expect(h.marked == joined)
    }
}
