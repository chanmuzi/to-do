import Foundation
import Testing
@testable import Editor

/// 선택 없이 누른 서식 단축키: 다음에 칠 글자의 서식(D-036).
@Suite struct TypingMarksTests {
    private func toggle(_ marked: String, _ wrap: EditorCommands.Wrap, marks: TypingMarks = TypingMarks()) -> TypingToggle {
        let s = Scenario(marked)
        return EditorCommands.toggleTyping(s.doc, caret: s.selection.location, wrap, marks: marks)
    }

    /// 정해 둔 서식으로 `typed`를 친 결과(편집기가 하는 것과 같게 기호 쌍 사이에 넣는다).
    private func type(_ marked: String, _ marks: TypingMarks, _ typed: String = "x") -> String? {
        let s = Scenario(marked)
        guard let place = EditorCommands.materialize(s.doc, caret: s.selection.location, marks: marks) else { return nil }
        let text = place.applied(to: s.text) as NSString
        let result = text.replacingCharacters(in: NSRange(location: place.selection.location, length: 0), with: typed)
        return Scenario.marked(result, selection: NSRange(location: place.selection.location + typed.utf16.count, length: 0))
    }

    @Test func turningAFormatOnInPlainTextWaitsForTheNextCharacter() {
        #expect(toggle("가|나", .bold) == .marks(TypingMarks(bold: true)))
        #expect(type("가|나", TypingMarks(bold: true)) == "가**x|**나")
        #expect(type("가|", TypingMarks(strike: true)) == "가~~x|~~")
        #expect(type("|", TypingMarks(code: true)) == "`x|`")
        // 한 번 더 누르면 없던 일이 된다.
        #expect(toggle("가|나", .bold, marks: TypingMarks(bold: true)) == .marks(TypingMarks()))
        // 여러 서식을 함께 켤 수 있다.
        #expect(type("가|", TypingMarks(bold: true, strike: true)) == "가**~~x|~~**")
        #expect(type("가|", TypingMarks(bold: true, highlight: 2)) == "가==**x|**=={회색}")
    }

    @Test func atTheEndOfARunTogglingOffStepsOutAndOnStepsBackIn() {
        // 구간 끝의 안쪽에서 끄면 커서가 구간 밖으로 나간다(자리는 그대로). 이어 치는 글자는 서식이 없다.
        #expect(toggle("가**나|**다", .bold) == .move(6))
        // 구간 바로 바깥에서 켜면 그 구간 안으로 들어간다. 새 구간을 따로 만들지 않는다.
        #expect(toggle("가**나**|다", .bold) == .move(4))
        #expect(toggle("가|**나**다", .bold) == .move(3))
        #expect(toggle("가**|나**다", .bold) == .move(1))
        // 다른 서식은 그 구간 안에 겹쳐 넣는다.
        #expect(toggle("가**나|**다", .strike) == .marks(TypingMarks(strike: true)))
        #expect(type("가**나|**다", TypingMarks(strike: true)) == "가**나~~x|~~**다")
    }

    @Test func togglingOffInTheMiddleOfARunSplitsItWhenTyping() {
        #expect(toggle("**가|나**", .bold) == .marks(TypingMarks(bold: false)))
        #expect(type("**가|나**", TypingMarks(bold: false)) == "**가**x|**나**")
        #expect(type("==가|나=={3}", TypingMarks(highlight: 0)) == "==가=={빨강}x|==나=={3}")
        // 바깥 구간만 끌 수는 없다(안쪽 구간이 겹쳐 있다).
        #expect(toggle("**가~~나|다~~라**", .bold) == .unavailable)
        #expect(type("**가~~나|다~~라**", TypingMarks(bold: false)) == nil)
    }

    @Test func nothingHappensInsideCode() {
        #expect(toggle("```\n코|드\n```", .bold) == .unavailable)
        #expect(toggle("`코|드`", .bold) == .unavailable)
        #expect(toggle("`코|드`", .code) == .marks(TypingMarks(code: false)))
        #expect(type("`코|드`", TypingMarks(code: false)) == "`코`x|`드`")
        #expect(type("`코|드`", TypingMarks(bold: true)) == nil)
    }

    @Test func lastInkIsAppliedOrClearedForTyping() {
        let base = Scenario("==가|=={4}")
        let choice = InkColor(.blue)
        #expect(EditorCommands.typingInk(base.doc, caret: base.selection.location, marks: TypingMarks(), color: choice,
                                         toggle: true) == .marks(TypingMarks(highlight: 0)))
        #expect(type("가|", TypingMarks(highlight: choice.id)) == "가==x|=={파랑}")
        #expect(type("==가|나==", TypingMarks(highlight: 3)) == "==가=={노랑}==x|=={빨강}==나==")
        #expect(type("가|", TypingMarks(underline: true)) == "가<u>x|</u>")
    }
}

@Suite struct LinkCommandTests {
    private func target(_ marked: String) -> LinkTarget? {
        let s = Scenario(marked)
        return EditorCommands.linkTarget(s.doc, selection: s.selection)
    }

    private func link(_ marked: String, _ address: String) -> String? {
        let s = Scenario(marked)
        guard let target = EditorCommands.linkTarget(s.doc, selection: s.selection) else { return nil }
        return s.applying(EditorCommands.setLink(s.doc, target: target, address: address))
    }

    @Test func selectionBecomesALink() {
        #expect(link("|문서| 보기", "https://a.example") == "[문서|](https://a.example) 보기")
        #expect(link("가 |**굵은** 글|", "https://a.example") == "가 [**굵은** 글|](https://a.example)")
        // 서식 구간의 글자만 골랐으면 그 안에 넣는다.
        #expect(link("**|굵은|** 글", "https://a.example") == "**[굵은|](https://a.example)** 글")
        // 주소를 비우면 만들지 않는다.
        #expect(link("|문서|", "  ") == nil)
    }

    @Test func caretOrSelectionInsideALinkEditsItsAddress() {
        #expect(link("[문|서](https://a.example)", "https://b.example") == "[문서|](https://b.example)")
        #expect(link("[|문서|](https://a.example)", "https://b.example") == "[문서|](https://b.example)")
        // 주소를 비우면 링크를 벗기고 글자만 남긴다.
        #expect(link("앞 [문|서](https://a.example) 뒤", "") == "앞 문서| 뒤")
        let s = Scenario("[문|서](https://a.example)")
        #expect(EditorCommands.linkAddress(s.doc, for: try! #require(target("[문|서](https://a.example)"))) == "https://a.example")
    }

    @Test func nothingToLink() {
        #expect(target("문|서") == nil)
        #expect(target("|가\n나|") == nil)
        #expect(target("```\n|code|\n```") == nil)
        #expect(target("`co|d|e`") == nil)
        #expect(link("|a [b] c|", "https://example.com") == "[a [b\\] c|](https://example.com)")
        #expect(target("|가 [나](https://a.example)| 다") == nil)
    }

    @Test func addressIsMadeSafeForTheSource() {
        #expect(EditorCommands.sanitizedAddress("  https://a.example/b c  ") == "https://a.example/b%20c")
        #expect(EditorCommands.sanitizedAddress("https://a.example/(x)") == "https://a.example/%28x%29")
        #expect(link("|문서|", "https://a.example/(x)") == "[문서|](https://a.example/%28x%29)")
        let doc = MarkdownDocument("[문서](https://a.example/%28x%29) 뒤")
        #expect(doc.lines[0].spans.first?.kind == .link("https://a.example/%28x%29"))
        // 고른 글자가 주소처럼 생겼으면 주소 칸에 미리 넣는다.
        for address in ["https://a.example", "http://[::1]/notes"] {
            let s = Scenario("|\(address)|")
            #expect(EditorCommands.linkAddress(s.doc, for: .new(s.selection)) == address)
        }
    }

    @Test func aLinkWithoutTextIsNotALink() {
        // 글자가 없는 링크는 화면에 아무것도 남지 않아 다시 고칠 수 없다. 글자 그대로 보인다.
        #expect(MarkdownDocument("[](https://a.example)").lines[0].markedSpans.isEmpty)
    }
}
