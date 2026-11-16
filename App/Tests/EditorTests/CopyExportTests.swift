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
        let text = "# 제목\n본문 **굵게**\n\n```swift\n> 코드는 그대로\n```"
        #expect(export(text).markdown == text)
    }

    @Test func sourceKeepsTheAppSyntaxForPastingBack() {
        let text = "> 토글\n\t[ ] ==형광=={3}"
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

    @Test func htmlCodeBlock() {
        let html = export("```swift\nlet a = 1 < 2\n```").html(highlightColors: colors)
        #expect(html == "<meta charset=\"utf-8\"><pre><code>let a = 1 &lt; 2</code></pre>")
    }
}
