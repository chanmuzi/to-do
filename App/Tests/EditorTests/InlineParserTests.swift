import Foundation
import Testing
@testable import Editor

@Suite struct InlineParserTests {
    private func spans(_ text: String) -> [InlineSpan] {
        MarkdownDocument(text).lines[0].spans
    }

    private func content(_ span: InlineSpan, in text: String) -> String {
        (text as NSString).substring(with: span.contentRange)
    }

    @Test func boldStrikeCode() {
        let text = "가 **굵게** 나 ~~취소~~ 다 `코드` 라"
        let found = spans(text)
        #expect(found.map(\.kind) == [.bold, .strike, .code])
        #expect(found.map { content($0, in: text) } == ["굵게", "취소", "코드"])
        #expect(found[0].openMarker.length == 2 && found[0].closeMarker.length == 2)
        #expect(found[2].openMarker.length == 1 && found[2].closeMarker.length == 1)
    }

    @Test func highlightColorsFollowD008() {
        let text = "==노랑== ==회색=={2} ==로즈=={3} ==블루=={4} ==없는색=={7}"
        let found = spans(text)
        #expect(found.map(\.kind) == [.highlight(1), .highlight(2), .highlight(3), .highlight(4)])
        // 색 번호는 닫는 기호에 포함된다(화면에서 함께 감춘다).
        #expect(found[0].closeMarker.length == 2)
        #expect(found[1].closeMarker.length == 5)
        #expect((text as NSString).substring(with: found[1].closeMarker) == "=={2}")
        // 모르는 번호는 글자로 남는다.
        #expect(spans("==없는색=={7}").isEmpty)
    }

    @Test func nestedSpansComeOuterFirst() {
        let text = "==**굵은 형광**=="
        let found = spans(text)
        #expect(found.map(\.kind) == [.highlight(1), .bold])
        #expect(content(found[1], in: text) == "굵은 형광")
    }

    @Test func codeSpanIsNotParsedInside() {
        let found = spans("`**그대로**`")
        #expect(found.map(\.kind) == [.code])
    }

    @Test func linksAndBareURLs() {
        let text = "[문서](https://a.example/x) 와 https://b.example/y."
        let found = spans(text)
        #expect(found.map(\.kind) == [.link("https://a.example/x"), .link("https://b.example/y")])
        #expect(content(found[0], in: text) == "문서")
        #expect((text as NSString).substring(with: found[0].closeMarker) == "](https://a.example/x)")
        // 주소만 적은 링크는 기호가 없고, 끝의 마침표는 주소에 넣지 않는다.
        #expect(found[1].openMarker.length == 0 && found[1].closeMarker.length == 0)
        #expect(content(found[1], in: text) == "https://b.example/y")
    }

    @Test func unclosedMarkersStayPlainText() {
        #expect(spans("**열기만").isEmpty)
        #expect(spans("==").isEmpty)
        #expect(spans("====").isEmpty)
        #expect(spans("a ` b").isEmpty)
        #expect(spans("[글자](주소 없음").isEmpty)
    }

    @Test func spansStartAfterTheLineMarker() {
        let doc = MarkdownDocument("[ ] **할 일**")
        let span = doc.lines[0].spans[0]
        #expect(span.range.location == 4)
        #expect(doc.string(in: span.contentRange) == "할 일")
    }
}
