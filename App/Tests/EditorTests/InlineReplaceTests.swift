import Foundation
import Testing
@testable import Editor

/// 보이지 않는 기호가 짝을 잃거나 빈 구간으로 남지 않게 지우고 덮어쓰는 규칙(D-036).
@Suite struct InlineReplaceTests {
    /// `|…|`로 고른 범위를 `text`로 바꾼 결과. 그대로 바꿔 써도 되는 경우는 `nil`.
    private func replace(_ marked: String, with text: String = "") -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.replacing(s.doc, s.selection, with: text))
    }

    private func backspace(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.deleteBackward(s.doc, selection: s.selection).edit)
    }

    private func forwardDelete(_ marked: String) -> String? {
        let s = Scenario(marked)
        return s.applying(EditorCommands.deleteForward(s.doc, selection: s.selection).edit)
    }

    @Test func plainEditsNeedNoRewrite() {
        #expect(replace("가|나|다") == nil)
        #expect(replace("**가|나|다**") == nil)
        #expect(replace("가|나|다 **라**", with: "x") == nil)
        #expect(replace("가|다", with: "x") == nil)
        // 구간이 통째로 든 선택은 그대로 지우면 된다.
        #expect(replace("가|나**다라**마|바") == nil)
    }

    @Test func deletingAllTheVisibleTextOfARunRemovesItsMarkers() {
        #expect(replace("가 **|굵게|** 나") == "가 | 나")
        #expect(replace("**~~|둘 다|~~**") == "|")
        #expect(replace("==|색|=={3} 뒤") == "| 뒤")
        #expect(replace("[|글자|](https://a.example)") == "|")
        #expect(replace("`|코드|`") == "|")
        // 선택이 구간 밖까지 걸쳐도 같다.
        #expect(replace("가|나**다라|** 마") == "가| 마")
    }

    @Test func typingOverAllTheVisibleTextKeepsTheFormat() {
        // 구간의 글자를 모두 고르고 치면 새 글자가 그 서식을 잇는다(기호는 그대로 두고 글자만 바꾼다).
        #expect(replace("가 **|굵게|** 나", with: "x") == nil)
        #expect(replace("**~~|둘 다|~~**", with: "x") == nil)
        // 구간보다 넓게 고르고 치면 구간은 사라지고 새 글자는 서식이 없다.
        #expect(replace("가| **굵게**| 나", with: "x") == nil)
        #expect(replace("가| **굵게|** 나", with: "x") == "가x| 나")
    }

    @Test func aMarkerCaughtInTheRangeSurvivesWhenItsRunDoes() {
        // 여는 기호만 든 선택: 남은 글자가 구간으로 남게 여는 기호를 넣는 글 뒤에 둔다.
        #expect(replace("가|나**다|라**") == "가|**라**")
        #expect(replace("가|나**다|라**", with: "x") == "가x|**라**")
        // 닫는 기호만 든 선택: 닫는 기호를 넣는 글 앞에 둔다.
        #expect(replace("**가|나** 다|라") == "**가**|라")
        #expect(replace("**가|나** 다|라", with: "x") == "**가**x|라")
        // 두 구간에 걸친 선택.
        #expect(replace("**가|나** 다 ~~라|마~~") == "**가**|~~마~~")
        // 링크와 형광펜의 기호도 통째로 남는다.
        #expect(replace("[가|나](https://a.example) 다|") == "[가](https://a.example)|")
        #expect(replace("|가 ==나|다=={2}") == "|==다=={2}")
    }

    @Test func multilineTextInsideARunSplitsTheRun() {
        #expect(replace("**가|다**", with: "x\ny") == "**가**x\ny**|다**")
        #expect(replace("**가|나|다**", with: "\n") == "**가**\n**|다**")
        #expect(replace("**|가**", with: "x\n") == "x\n**|가**")
        #expect(replace("**가|**", with: "\nx") == "**가**\nx|")
        #expect(replace("가|나", with: "x\ny") == nil)
    }

    @Test func backspaceDeletesAVisibleCharacterNeverJustAMarker() {
        // 구간 바로 뒤(기호 바깥)에서: 기호를 건너 구간의 마지막 글자를 지운다.
        #expect(backspace("가**나다**|라") == "가**나|**라")
        // 구간의 앞(기호 안쪽)에서: 기호를 건너 구간 앞의 글자를 지운다.
        #expect(backspace("가나**|다**") == "가|**다**")
        // 링크의 주소와 형광펜의 색 번호를 건너뛴다.
        #expect(backspace("[글자](https://a.example)|") == "[글|](https://a.example)")
        #expect(backspace("==형광=={4}| 뒤") == "==형|=={4} 뒤")
        // 구간의 마지막 한 글자를 지우면 기호도 사라진다.
        #expect(backspace("가**나|**다") == "가|다")
        #expect(backspace("가**나**|다") == "가|다")
        #expect(backspace("**~~나|~~**") == "|")
        #expect(backspace("[글|](https://a.example) 뒤") == "| 뒤")
        // 조합형 글자(이모지)는 통째로 지운다.
        #expect(backspace("**a👍🏽**|") == "**a|**")
    }

    @Test func forwardDeleteFollowsTheSameRules() {
        #expect(forwardDelete("가|**나다**라") == "가|**다**라")
        #expect(forwardDelete("**가나|**다") == "**가나|**")
        #expect(forwardDelete("가|**나**다") == "가|다")
        #expect(forwardDelete("**|나**다") == "|다")
        #expect(forwardDelete("가|[글](https://a.example)") == "가|")
    }

    @Test func backspaceAtTheVisualStartOfAParagraphJoinsTheLineNotTheMarker() {
        // 문단이 서식 구간으로 시작하면 커서 앞에는 감춘 여는 기호가 있다. 기호가 아니라 줄바꿈을 지운다.
        #expect(backspace("앞\n**|굵게**") == "앞**|굵게**")
        #expect(EditorCommands.deleteBackward(MarkdownDocument("**굵게**"), selection: NSRange(location: 2, length: 0)) == .ignore)
        #expect(forwardDelete("**굵게|**\n- 뒤") == "**굵게|**뒤")
        #expect(EditorCommands.deleteForward(MarkdownDocument("**굵게**"), selection: NSRange(location: 4, length: 0)) == .ignore)
    }
}

@Suite struct CodeFenceGuardTests {
    // 0 앞 / 1 ``` / 2 code / 3 more / 4 ``` / 5 뒤
    let doc = MarkdownDocument("앞\n```\ncode\nmore\n```\n뒤")

    private func breaks(_ location: Int, _ length: Int) -> Bool {
        EditorCommands.breaksCodeFence(doc, NSRange(location: location, length: length))
    }

    @Test func rangesThatTouchOneFenceAreRefused() {
        let lines = doc.lines
        // 여는 줄: 앞의 줄바꿈, 줄 자체, 뒤의 줄바꿈.
        #expect(breaks(lines[0].end, 1))
        #expect(breaks(lines[1].start, 3))
        #expect(breaks(lines[1].end, 1))
        #expect(breaks(lines[0].start, lines[2].end))
        // 닫는 줄도 같다.
        #expect(breaks(lines[3].end, 1))
        #expect(breaks(lines[4].start, 2))
        #expect(breaks(lines[4].end, 1))
        #expect(breaks(lines[2].start, lines[5].end - lines[2].start))
    }

    @Test func rangesInsideOutsideOrOverTheWholeBlockAreFine() {
        let lines = doc.lines
        #expect(!breaks(lines[2].start, 2))
        #expect(!breaks(lines[2].end, 1))
        #expect(!breaks(lines[2].start, lines[3].end - lines[2].start))
        #expect(!breaks(0, 1))
        #expect(!breaks(lines[5].start, 1))
        #expect(!breaks(lines[1].start, lines[4].end - lines[1].start))
        #expect(!breaks(lines[1].start, lines[5].start - lines[1].start))
        #expect(!breaks(0, doc.length))
        #expect(!breaks(lines[1].start, 0))
    }
}

@Suite struct CodeBlockKeyTests {
    private func backspace(_ marked: String) -> KeyOutcome {
        let s = Scenario(marked)
        return EditorCommands.deleteBackward(s.doc, selection: s.selection)
    }

    private func forwardDelete(_ marked: String) -> KeyOutcome {
        let s = Scenario(marked)
        return EditorCommands.deleteForward(s.doc, selection: s.selection)
    }

    private func applied(_ marked: String, _ outcome: KeyOutcome) -> String? {
        Scenario(marked).applying(outcome.edit)
    }

    @Test func backspaceAtTheStartOfAnEmptyBlockRemovesTheBlock() {
        #expect(applied("앞\n```swift\n|\n```\n뒤", backspace("앞\n```swift\n|\n```\n뒤")) == "앞\n|\n뒤")
        #expect(applied("```\n|\n```", backspace("```\n|\n```")) == "|")
        // 글이 있거나 줄이 더 있으면 ``` 줄과 합쳐지지 않게 아무것도 하지 않는다.
        #expect(backspace("```\n|code\n```") == .ignore)
        #expect(backspace("```\n|\ncode\n```") == .ignore)
        // 블록 안의 다른 줄에서는 보통의 지우기다.
        #expect(backspace("```\ncode\n|more\n```") == .passThrough)
        #expect(backspace("```\nco|de\n```") == .passThrough)
    }

    @Test func backspaceRightBelowABlockGoesIntoTheBlock() {
        // 빈 줄이면 그 줄을 지우고, 글이 있으면 커서만 블록의 마지막 줄 끝으로 간다.
        #expect(applied("```\ncode\n```\n|", backspace("```\ncode\n```\n|")) == "```\ncode|\n```")
        #expect(backspace("```\ncode\n```\n|뒤") == .select(NSRange(location: 8, length: 0)))
    }

    @Test func forwardDeleteNeverJoinsAFenceLine() {
        #expect(forwardDelete("```\ncode|\n```") == .ignore)
        #expect(forwardDelete("```\ncode|\nmore\n```") == .passThrough)
        #expect(forwardDelete("앞|\n```\ncode\n```") == .ignore)
        // 블록 바로 위의 빈 줄은 지울 수 있다.
        #expect(applied("|\n```\ncode\n```", forwardDelete("|\n```\ncode\n```")) == "```\n|code\n```")
    }

    @Test func arrowsOutOfABlockAtTheEdgeOfTheDocumentMakeAParagraph() {
        func down(_ marked: String) -> String? {
            let s = Scenario(marked)
            return s.applying(EditorCommands.leaveCodeBlockDownward(s.doc, selection: s.selection))
        }
        func up(_ marked: String) -> String? {
            let s = Scenario(marked)
            return s.applying(EditorCommands.leaveCodeBlockUpward(s.doc, selection: s.selection))
        }
        #expect(down("```\na\nb|\n```") == "```\na\nb\n```\n|")
        #expect(down("\t```\n\tb|\n\t```") == "\t```\n\tb\n\t```\n\t|")
        // 닫히지 않은 블록은 닫는 줄도 넣는다.
        #expect(down("```\nb|") == "```\nb\n```\n|")
        // 마지막 줄이 아니거나, 블록 아래에 줄이 있으면 보통의 이동이다.
        #expect(down("```\na|\nb\n```") == nil)
        #expect(down("```\nb|\n```\n뒤") == nil)
        #expect(up("```\n|a\nb\n```") == "|\n```\na\nb\n```")
        #expect(up("```\na\n|b\n```") == nil)
        #expect(up("앞\n```\n|a\n```") == nil)
    }
}
