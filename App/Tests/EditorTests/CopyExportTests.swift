import Foundation
import Testing
@testable import Editor

@Suite struct CopyExportTests {
    private let colors = [1: "#FFEB85", 2: "#E4E4E4", 3: "#FFD2CC", 4: "#CFE5FF"]

    private func export(_ text: String) -> CopyExport {
        let doc = MarkdownDocument(text)
        return CopyExport(doc, selection: NSRange(location: 0, length: doc.length))
    }

    @Test func markdownUsesStandardSyntax() {
        let result = export(DemoNote.text).markdown
        #expect(result == """
        - [x] 스탠드업 회의록 공유
        - [ ] **PR #482** 리뷰
            - [ ] 포커스 전환 애니메이션 확인
            - 리뷰 코멘트 2건에 답글
        - [ ] ==배포 체크리스트 확인==
        - 지난주에서 넘어온 것
            - [ ] **온보딩 문서** 초안 마무리
            - [ ] `feature/quick-capture` 브랜치 정리
                - 리베이스한 뒤 푸시
            - [x] 주간 리포트 제출
        """)
    }

    @Test func markdownDropsTheHighlightColorSuffix() {
        #expect(export("가 ==회색=={2} 나 ==블루=={4} 다 ==노랑==").markdown == "가 ==회색== 나 ==블루== 다 ==노랑==")
        // 코드 안의 같은 글자는 건드리지 않는다.
        #expect(export("`==코드=={2}`").markdown == "`==코드=={2}`")
    }

    @Test func markdownKeepsHeadingsParagraphsAndCode() {
        let text = "# 제목\n본문 **굵게**\n\n```swift\n+ 코드는 그대로\n```"
        #expect(export(text).markdown == text)
    }

    @Test func sourceKeepsTheAppSyntaxForPastingBack() {
        let text = "+ 토글\n\t[ ] ==형광=={3}"
        #expect(export(text).source == text)
    }

    @Test func selectionFromContentStartIncludesTheHiddenMarker() {
        let doc = MarkdownDocument("[ ] 가\n[x] 나")
        let fromContent = CopyExport(doc, selection: NSRange(location: 4, length: doc.length - 4))
        #expect(fromContent.source == "[ ] 가\n[x] 나")
        #expect(fromContent.markdown == "- [ ] 가\n- [x] 나")
        // 글자 가운데서 시작하면 기호 없이 그 글자만 나간다.
        let partial = MarkdownDocument("[ ] 가나다")
        #expect(CopyExport(partial, selection: NSRange(location: 5, length: 2)).markdown == "나다")
    }

    @Test func nestedSelectionStartsAtTheLeftEdge() {
        let doc = MarkdownDocument(DemoNote.text)
        let range = NSRange(location: doc.lines[6].start, length: doc.lines[8].end - doc.lines[6].start)
        #expect(CopyExport(doc, selection: range).markdown == """
        - [ ] **온보딩 문서** 초안 마무리
        - [ ] `feature/quick-capture` 브랜치 정리
            - 리베이스한 뒤 푸시
        """)
    }

    @Test func copyingFromInsideACodeBlockExportsRawCode() {
        let doc = MarkdownDocument("```\n# 제목 아님\n- 목록 아님\n```\n뒤")
        let range = NSRange(location: doc.lines[1].start, length: doc.lines[4].end - doc.lines[1].start)
        let result = CopyExport(doc, selection: range)
        #expect(result.markdown == "# 제목 아님\n- 목록 아님\n뒤")
        #expect(result.html(highlightColors: colors).contains("<pre><code># 제목 아님\n- 목록 아님</code></pre><p>뒤</p>"))
    }

    @Test func htmlNestsToggleChildrenAndMarksTodos() {
        let html = export(DemoNote.text).html(highlightColors: colors)
        #expect(html == "<meta charset=\"utf-8\"><ul>"
            + "<li><input type=\"checkbox\" disabled checked> 스탠드업 회의록 공유</li>"
            + "<li><input type=\"checkbox\" disabled> <strong>PR #482</strong> 리뷰<ul>"
            + "<li><input type=\"checkbox\" disabled> 포커스 전환 애니메이션 확인</li>"
            + "<li>리뷰 코멘트 2건에 답글</li></ul></li>"
            + "<li><input type=\"checkbox\" disabled> <mark style=\"background-color:#FFEB85\">배포 체크리스트 확인</mark></li>"
            + "<li>지난주에서 넘어온 것<ul>"
            + "<li><input type=\"checkbox\" disabled> <strong>온보딩 문서</strong> 초안 마무리</li>"
            + "<li><input type=\"checkbox\" disabled> <code>feature/quick-capture</code> 브랜치 정리<ul>"
            + "<li>리베이스한 뒤 푸시</li></ul></li>"
            + "<li><input type=\"checkbox\" disabled checked> 주간 리포트 제출</li></ul></li>"
            + "</ul>")
    }

    @Test func htmlInlineStylesAndEscaping() {
        let html = export("# a < b\n~~취소~~ ==색=={4} [링크](https://x.example/?a=1&b=2) `<tag>`").html(highlightColors: colors)
        #expect(html == "<meta charset=\"utf-8\"><h1>a &lt; b</h1>"
            + "<p><s>취소</s> <mark style=\"background-color:#CFE5FF\">색</mark> "
            + "<a href=\"https://x.example/?a=1&amp;b=2\">링크</a> <code>&lt;tag&gt;</code></p>")
    }

    @Test func singleLineSelectionLeavesTheHiddenMarkerOut() {
        let doc = MarkdownDocument("- alpha beta\n- gamma")
        let word = CopyExport(doc, selection: NSRange(location: 2, length: 5))
        #expect(word.source == "alpha")
        #expect(word.markdown == "alpha")
        #expect(word.html(highlightColors: colors) == "<meta charset=\"utf-8\"><p>alpha</p>")
        // 줄 맨 앞부터 골라도 그 줄 안에서 끝나면 글자만 나간다.
        #expect(CopyExport(doc, selection: NSRange(location: 0, length: 7)).markdown == "alpha")
        // 줄 끝을 넘어가면 기호까지 나간다.
        #expect(CopyExport(doc, selection: NSRange(location: 2, length: 11)).markdown == "- alpha beta\n")
        #expect(CopyExport(doc, selection: NSRange(location: 2, length: 16)).markdown == "- alpha beta\n- gam")
        // 들여 쓴 줄도 같다.
        let nested = MarkdownDocument("\t[ ] 가나다\n끝")
        #expect(CopyExport(nested, selection: NSRange(location: 5, length: 3)).markdown == "가나다")
    }

    @Test func lastLineSelectedOnlyUpToItsMarkerIsDropped() {
        let doc = MarkdownDocument("- alpha\n- gamma\n- delta")
        // ⇧↓ : 윗줄 글자 시작에서 아랫줄 글자 시작까지.
        let export = CopyExport(doc, selection: NSRange(location: 2, length: 8))
        #expect(export.source == "- alpha")
        #expect(export.markdown == "- alpha")
        #expect(export.html(highlightColors: colors) == "<meta charset=\"utf-8\"><ul><li>alpha</li></ul>")
        // 두 줄을 지나 셋째 줄 글자 시작까지.
        #expect(CopyExport(doc, selection: NSRange(location: 2, length: 16)).markdown == "- alpha\n- gamma")
        // 빈 항목은 줄 머리가 전부이므로 고른 그대로 둔다.
        let empty = MarkdownDocument("- alpha\n- ")
        #expect(CopyExport(empty, selection: NSRange(location: 0, length: empty.length)).markdown == "- alpha\n- ")
    }

    @Test func htmlLinksOnlyWebAndMailAddresses() {
        let html = export("[click](javascript:alert(1)) [파일](file:///etc/passwd) [앱](x-app://open) [상대](../a)")
            .html(highlightColors: colors)
        #expect(!html.contains("href"))
        #expect(!html.contains("javascript"))
        #expect(html == "<meta charset=\"utf-8\"><p>click) 파일 앱 상대</p>")
        let allowed = export("[웹](HTTPS://a.example/x) [메일](mailto:a@b.example) [옛](http://a.example)")
            .html(highlightColors: colors)
        #expect(allowed == "<meta charset=\"utf-8\"><p><a href=\"HTTPS://a.example/x\">웹</a> "
            + "<a href=\"mailto:a@b.example\">메일</a> <a href=\"http://a.example\">옛</a></p>")
        // 글자로는 원문 그대로 나간다.
        #expect(export("[click](javascript:alert(1))").markdown == "[click](javascript:alert(1))")
    }

    @Test func linkPolicyAllowsOnlyHTTPAndMail() {
        #expect(LinkPolicy.openableURL(" https://a.example ")?.absoluteString == "https://a.example")
        #expect(LinkPolicy.openableURL("mailto:a@b.example") != nil)
        for address in ["javascript:alert(1)", "JavaScript:alert(1)", "file:///etc/passwd", "x-app://open", "data:text/html,x", "a.example", "/path", ""] {
            #expect(LinkPolicy.openableURL(address) == nil, "\(address)")
        }
    }

    @Test func htmlCodeBlock() {
        let html = export("```swift\nlet a = 1 < 2\n```").html(highlightColors: colors)
        #expect(html == "<meta charset=\"utf-8\"><pre><code>let a = 1 &lt; 2</code></pre>")
    }
}
