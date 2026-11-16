import AppKit
import Testing
@testable import Editor

/// 영문자나 숫자에 붙은 `**`, `~~`, `==`를 읽는 규칙(D-038)과, 그 규칙 때문에 적을 수 없는 편집을 다루는 방법.
@MainActor
@Suite struct GluedRunTests {
    typealias Key = EditorShortcuts.Key

    /// 줄의 구간들: 종류와 그 안의 글.
    private static func runs(_ text: String) -> [String] {
        let doc = MarkdownDocument(text)
        return doc.lines[0].spans.filter { $0.kind != .escape }.map { span in
            let name: String
            switch span.kind {
            case .bold: name = "굵게"
            case .strike: name = "취소선"
            case .highlight: name = "형광펜"
            case .code: name = "코드"
            case .link: name = "링크"
            case .escape: name = "막음"
            }
            return "\(name):\(doc.string(in: span.contentRange))"
        }
    }

    /// 원문과, 구간으로 읽혀야 하는 것. 글, 코드처럼 쓴 글, 한글을 섞었다.
    static let table: [(source: String, runs: [String])] = [
        // 여는 기호 앞이 영문자나 숫자가 아니다: 닫는 기호 뒤에 무엇이 와도 구간이다.
        ("**굵게**", ["굵게:굵게"]),
        ("word **bold** word", ["굵게:bold"]),
        ("**believ**able", ["굵게:believ"]),
        ("**중요**하다", ["굵게:중요"]),
        ("앞**굵은 글**뒤", ["굵게:굵은 글"]),
        ("한글**bold text**abc", ["굵게:bold text"]),
        ("(==강조==)", ["형광펜:강조"]),
        ("값은 ~~10~~20", ["취소선:10"]),
        // 여는 기호가 영문자나 숫자 바로 뒤: 한 낱말이고 닫는 기호 뒤가 영문자나 숫자가 아닐 때만 구간이다.
        ("un**believ**", ["굵게:believ"]),
        ("un**believ** it", ["굵게:believ"]),
        ("3**개** 남음", ["굵게:개"]),
        ("API==키==를 넣는다", ["형광펜:키"]),
        ("v2~~beta~~.", ["취소선:beta"]),
        ("foo**bar** baz", ["굵게:bar"]),
        ("2024==년=={2} 계획", ["형광펜:년"]),
        // 양쪽 모두 영문자나 숫자에 붙었다: 글자다.
        ("un**believ**able", []),
        ("foo**bar**baz", []),
        ("2**3**4", []),
        ("x==1&y==2", []),
        ("a==b==c", []),
        ("f(a==b,c==d)", []),
        // 영문자나 숫자 뒤에서 열었는데 사이의 글이 한 낱말이 아니다: 여는 기호는 글자이고 뒤는 다시 읽는다.
        ("a==b 인지 ==확인== 하자", ["형광펜:확인"]),
        ("x==1 이면 ==중요==", ["형광펜:중요"]),
        ("a==b,==확인==", ["형광펜:확인"]),
        ("a==b(==확인==)", ["형광펜:확인"]),
        ("if a==b || c== 1", []),
        ("foo**bar baz** qux", []),
        ("2**3**4 and **b**", ["굵게:b"]),
        ("n**2 + m**2 은 **제곱합**", ["굵게:제곱합"]),
        ("ptr**p, int**q", []),
        // 공백 조건(전과 같다).
        ("if a == 1 && b == 2", []),
        ("char **argv, int **p", []),
        ("2 ** 3 ** 4", []),
        ("==a == b==", ["형광펜:a == b"]),
        // 막은 글자와 인라인 코드.
        ("a\\=\\=b==", []),
        ("un\\*\\*believ\\*\\*", []),
        ("`a==b` 는 ==같다==", ["코드:a==b", "형광펜:같다"]),
        ("x`**`y **굵게**", ["코드:**", "굵게:굵게"]),
    ]

    @Test func tableOfGluedMarkers() {
        #expect(Self.table.count >= 30)
        for row in Self.table {
            #expect(Self.runs(row.source) == row.runs, "\(row.source)")
        }
    }

    /// 영문자나 숫자 바로 뒤에서 연 기호를 손으로 쳐서 닫아도 서식이 되지 않는다. 친 그대로 보인다.
    @Test(arguments: ["un**believ**a", "2**3**4", "a==b==c", "x==1&y==2", "v1~~2~~"])
    func markersTypedAfterAWordCharacterStayLiteral(typed: String) throws {
        let h = try EditorHarness()
        h.type(typed)
        let line = h.document.lines[0]
        #expect(line.spans.allSatisfy { $0.kind == .escape }, "\(h.editor.text)")
        // 화면에는 친 글자가 그대로 보인다(백슬래시만 감춘다).
        let hidden = line.markers.map(\.range)
        let units = (line.contentStart..<line.end).filter { position in !hidden.contains { NSLocationInRange(position, $0) } }
            .map { h.document.units[$0] }
        #expect(String(utf16CodeUnits: units, count: units.count) == typed)
        #expect(h.beeps == 0)
        // 다시 읽어도 같다.
        #expect(MarkdownDocument(h.editor.text).lines[0].spans.allSatisfy { $0.kind == .escape })
    }

    /// 낱말을 붙여도 서식을 말없이 풀지 않는다. 적을 수 있는 쪽(앞)은 그대로 구간이고, 적을 수 없게 되는
    /// 편집(양쪽 모두 붙음)은 넣지 않고 알린다.
    @Test func joiningWordsAroundARunNeverStripsIt() throws {
        let h = try EditorHarness.at("foo |**bar** baz")
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "foo**bar** baz")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        #expect(h.beeps == 0)
        h.place(at: 11)
        h.press(NSResponder.backspace)
        #expect(h.editor.text == "foo**bar** baz")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        #expect(h.beeps == 1)
        // 뒤를 먼저 붙이고 앞을 붙여도 같다.
        let k = try EditorHarness.at("foo **bar** |baz")
        k.press(NSResponder.backspace)
        #expect(k.editor.text == "foo **bar**baz")
        k.place(at: 4)
        k.press(NSResponder.backspace)
        #expect(k.editor.text == "foo **bar**baz")
        #expect(k.document.lines[0].spans.map(\.kind) == [.bold])
        #expect(k.beeps == 1)
    }

    @Test func typingAWordCharacterThatWouldUnformatARunIsRejectedWithTheBeep() throws {
        // 단축키로 건 서식은 영문자 뒤에서도 걸린다.
        let h = try EditorHarness.at("un|")
        h.key(Key.b, "b", .command)
        h.type("believ")
        #expect(h.editor.text == "un**believ**")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        // 구간 밖으로 나가 영문자를 치면 양쪽이 모두 붙는다. 넣지 않는다.
        h.press(NSResponder.right)
        h.type("a")
        #expect(h.editor.text == "un**believ**")
        #expect(h.beeps == 1)
        // 한글이나 문장 부호는 된다.
        h.type("다")
        #expect(h.editor.text == "un**believ**다")
        #expect(h.document.lines[0].spans.map(\.kind) == [.bold])
        // 여러 낱말의 구간 바로 앞에 영문자를 치는 것도 적을 수 없다.
        let k = try EditorHarness.at("가 |**굵은 글** 끝")
        k.type("x")
        #expect(k.editor.text == "가 **굵은 글** 끝")
        #expect(k.beeps == 1)
        k.type("나")
        #expect(k.editor.text == "가 나**굵은 글** 끝")
        #expect(k.document.lines[0].spans.map(\.kind) == [.bold])
        // 한 낱말의 구간 앞에는 칠 수 있다.
        let j = try EditorHarness.at("가 |**굵게** 끝")
        j.type("x")
        #expect(j.editor.text == "가 x**굵게** 끝")
        #expect(j.document.lines[0].spans.map(\.kind) == [.bold])
        #expect(j.beeps == 0)
    }

    /// 영문자 뒤에서 연 구간은 한 낱말까지만 적을 수 있다. 그 안에 낱말을 더해 읽히지 않게 되는 편집도 넣지 않는다
    /// (기호가 글자로 드러나지 않는다).
    @Test func editsInsideARunThatWouldExposeItsMarkersAreRejected() throws {
        let h = try EditorHarness.at("b==광|== 끝")
        h.type(" ")
        // 구간 끝에서 친 공백은 기호 밖에 놓인다. 이어 친 글자를 구간에 들이면 두 낱말이 되므로 넣지 않는다.
        h.type("a")
        #expect(h.editor.text == "b==광==  끝")
        #expect(h.document.lines[0].spans.map(\.kind) == [.highlight(1)])
        #expect(h.beeps == 1)
        // 한 낱말로 남는 편집은 된다.
        let k = try EditorHarness.at("b==광|== 끝")
        k.type("a")
        #expect(k.editor.text == "b==광a== 끝")
        #expect(k.beeps == 0)
        // 겹친 서식은 한 낱말로 본다.
        #expect(Self.runs("a==**굵게**== 끝") == ["형광펜:**굵게**", "굵게:굵게"])
    }

    /// 정해 둔 서식으로 여러 줄을 붙일 때, 영문자 뒤라서 읽히지 않는 첫 줄은 감싸지 않는다.
    @Test func pendingFormatSkipsAFirstPastedLineThatCouldNotBeRead() throws {
        let h = try EditorHarness.at("b|")
        h.key(Key.x, "x", [.command, .shift])
        h.paste("두 줄\n글")
        #expect(h.editor.text == "b두 줄\n~~글~~")
    }

    /// 붙여 넣는 글의 서식이 그 자리에서 읽히지 않으면 전처럼 기호를 벗기고 글자만 넣는다.
    @Test func pastedFormattingThatCannotBeReadIsPastedAsText() throws {
        let h = try EditorHarness.at("foo|")
        h.paste("**굵은 글**")
        #expect(h.editor.text == "foo굵은 글")
        #expect(h.beeps == 0)
    }
}
