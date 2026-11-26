import AppKit
import Testing
@testable import Editor

/// 글자처럼 생긴 기호를 서식으로 읽지 않는 규칙과 백슬래시(D-036의 13번).
@Suite struct InlineFlankingTests {
    private func spans(_ text: String) -> [InlineSpan] {
        MarkdownDocument(text).lines[0].spans
    }

    private func kinds(_ text: String) -> [InlineSpan.Kind] {
        spans(text).map(\.kind)
    }

    /// 서식이 아닌 글: 아무 기호도 감추지 않는다.
    @Test(arguments: [
        "if a == 1 && b == 2",
        "char **argv, int **p",
        "2 ** 3 ** 4",
        "2**3**4",
        "a.com/?x==1&y==2",
        "use ` and ` here",
        "a ~~ b ~~ c",
        "**",
        "****",
        "** 굵게 아님 **",
        "가 **나 ** 다",
        "snake_case_name",
        "someone@example.com",
        "C:\\path\\to",
        "#hashtag",
        "a - b",
        "1. 첫째",
        "＊＊전각＊＊ ＝＝전각＝＝ ｀전각｀",
        "x = y * 2 * z",
        "`",
        "``",
    ])
    func literalTextHidesNothing(text: String) {
        #expect(spans(text).isEmpty, "\(text)")
    }

    @Test func urlsStayWhole() {
        #expect(kinds("https://a.com/?x==1&y==2") == [.link("https://a.com/?x==1&y==2")])
        #expect(kinds("보기 https://a.example/a**b**c 끝") == [.link("https://a.example/a**b**c")])
    }

    @Test func flankedMarkersAreFormatting() {
        #expect(kinds("**굵게**") == [.bold])
        #expect(kinds("앞**굵게**뒤") == [.bold])
        #expect(kinds("**중요**하다") == [.bold])
        #expect(kinds("word **bold** word") == [.bold])
        #expect(kinds("un**believ**") == [.bold])
        #expect(kinds("**believ**able") == [.bold])
        #expect(kinds("==a == b==") == [.highlight(1)])
        #expect(kinds("==형광=={3}") == [.highlight(3)])
        #expect(kinds("~~a~~ `b` ==c==") == [.strike, .code, .highlight(1)])
        // 앞의 글자 같은 기호는 그대로 두고 뒤의 서식만 읽는다.
        #expect(kinds("2**3**4 and **b**") == [.bold])
        let line = MarkdownDocument("2**3**4 and **b**").lines[0]
        #expect(line.spans[0].range == NSRange(location: 12, length: 5))
        // 닫는 기호를 찾을 때 인라인 코드와 막은 글자는 건너뛴다.
        #expect(kinds("**a `**` b**") == [.bold, .code])
        #expect(spans("**a\\*\\*b**").first?.contentRange == NSRange(location: 2, length: 6))
    }

    @Test func backslashEscapesAreHiddenAndKeptInTheSource() {
        #expect(kinds("\\*\\*글\\*\\*") == [.escape, .escape, .escape, .escape])
        #expect(kinds("\\=\\=a\\=\\=") == [.escape, .escape, .escape, .escape])
        #expect(kinds("\\~ \\` \\[ \\] \\\\") == [.escape, .escape, .escape, .escape, .escape])
        // 막을 글자가 아니면 백슬래시는 글자다.
        #expect(kinds("C:\\path \\n \\a").isEmpty)
        // 인라인 코드 안에서는 백슬래시도 글자다.
        #expect(kinds("`a\\*b`") == [.code])
        // 막은 `[`는 링크를 열지 않는다. 링크 글자 안의 막은 `]`는 링크를 닫지 않는다.
        #expect(kinds("\\[글](https://a.example)").first == .escape)
        let link = spans("[a\\]b](https://a.example)")
        #expect(link.first?.kind == .link("https://a.example"))
        #expect(link.first?.contentRange == NSRange(location: 1, length: 4))
    }

    @Test func escapedText() {
        #expect(EditorCommands.escaped("**a**") == "\\*\\*a\\*\\*")
        #expect(EditorCommands.escaped("\\*a*") == "\\*a\\*")
        #expect(EditorCommands.escaped("=={2}") == "\\=\\={2}")
    }
}

/// 백슬래시로 막은 글자는 한 글자처럼 다룬다: 커서가 사이에 놓이지 않고, 지우면 백슬래시도 지워진다.
@MainActor
@Suite struct EscapeEditingTests {
    @Test func caretNeverRestsBetweenTheBackslashAndItsCharacter() throws {
        let h = try EditorHarness("a\\*b")
        h.caret(at: 0)
        var seen: [Int] = []
        for _ in 0..<3 {
            h.press(NSResponder.right)
            seen.append(h.editor.selectedRange.location)
        }
        #expect(seen == [1, 3, 4])
        seen = []
        for _ in 0..<3 {
            h.press(NSResponder.left)
            seen.append(h.editor.selectedRange.location)
        }
        #expect(seen == [3, 1, 0])
        // 줄 맨 앞의 막은 글자 앞.
        let k = try EditorHarness("\\*b")
        k.caret(at: 2)
        k.press(NSResponder.left)
        #expect(k.marked == "|\\*b")
        k.type("x")
        #expect(k.marked == "x|\\*b")
    }

    @Test func deletingAnEscapedCharacterRemovesTheBackslash() throws {
        let h = try EditorHarness.at("a\\*|b")
        h.press(NSResponder.backspace)
        #expect(h.marked == "a|b")
        h.undo()
        #expect(h.editor.text == "a\\*b")
        h.place(at: 1)
        h.press(NSResponder.forwardDelete)
        #expect(h.marked == "a|b")
        // 덮어쓰기.
        let k = try EditorHarness("a\\*b")
        k.caret(at: 1)
        k.press(NSResponder.shiftRight)
        #expect(k.marked == "a|\\*|b")
        k.type("x")
        #expect(k.marked == "ax|b")
    }

    /// 리뷰에서 나온 경우: `2 ** 3 ** 4`를 치고 ⌫를 다섯 번 누르면 친 글자 다섯만 지워진다(전에는 `2 `만 남았다).
    @Test func literalStarsAreTypedAndDeletedLikeText() throws {
        let h = try EditorHarness()
        h.type("2 ** 3 ** 4")
        #expect(h.marked == "2 ** 3 ** 4|")
        #expect(h.document.lines[0].spans.isEmpty)
        h.press(NSResponder.backspace, times: 5)
        #expect(h.marked == "2 ** 3|")
    }

    @Test func typingABackslashBeforeAMarkerMakesItLiteral() throws {
        let h = try EditorHarness()
        h.type("\\*\\*글\\*\\*")
        #expect(h.editor.text == "\\*\\*글\\*\\*")
        #expect(h.document.lines[0].markedSpans.isEmpty)
        // 화면에는 백슬래시가 보이지 않는다.
        #expect(try h.fontSize(line: 0, at: NSRange(location: 0, length: 1)) == [EditorMetrics.hiddenFontSize])
        #expect(try h.fontSize(line: 0, at: NSRange(location: 1, length: 1)).allSatisfy { $0 > 1 })
    }
}

/// 서식 명령이 글자처럼 생긴 기호를 만나도 서식이 뒤집히지 않는다.
@Suite struct WrapSafetyTests {
    private func wrap(_ marked: String, _ wrap: EditorCommands.Wrap) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.toggleWrap(s.doc, selection: s.selection, wrap))
    }

    private func highlight(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.setInk(s.doc, selection: s.selection, color: InkColor(.yellow), toggle: true))
    }

    @Test func wrappingTextThatContainsTheMarkerEscapesOrRefuses() {
        // 띄어 쓴 `==`는 닫는 기호로 읽히지 않으므로 그대로 감싼다.
        #expect(highlight("|a == b|") == "==|a == b|=={노랑}")
        #expect(MarkdownDocument("==a == b==").lines[0].spans.map(\.kind) == [.highlight(1)])
        // 닫는 기호로 읽힐 글자는 백슬래시로 막는다.
        #expect(highlight("|a==b|") == "==|a\\=\\=b|=={노랑}")
        #expect(wrap("|2**3|", .bold) == "**|2\\*\\*3|**")
        #expect(wrap("|a~~b|", .strike) == "~~|a\\~\\~b|~~")
        // 인라인 코드 안에는 백슬래시를 쓸 수 없다. 백틱이 든 글은 코드로 감싸지 않는다.
        #expect(wrap("|a ` b`c|", .code) == nil)
        // 가장자리 공백은 감싸지 않는다.
        #expect(wrap("가| 나 |다", .bold) == "가 **|나|** 다")
        #expect(wrap("가|  |다", .bold) == nil)
    }

    @Test func wrappingInsideAnAsciiWordIsRefusedBecauseItWouldNotBeRead() {
        #expect(wrap("un|believ|able", .bold) == nil)
        #expect(wrap("un|believ|", .bold) == "un**|believ|**")
        #expect(wrap("|believ|able", .bold) == "**|believ|**able")
        #expect(wrap("믿|을 수|없다", .bold) == "믿**|을 수|**없다")
    }
}
