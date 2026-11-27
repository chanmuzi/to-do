import AppKit
import Testing
@testable import Editor

@Suite struct NotionHTMLImportTests {
    @Test func nestedExportedBlocks() {
        let html = """
        <ul class="toggle"><li><details><summary>계획 &amp; 메모</summary>
          <ul class="to-do-list"><li><div class="checkbox checkbox-on"></div>
            <span class="to-do-children-checked">초안</span><div class="indented">
              <ul class="bulleted-list"><li>자료</li></ul></div></li></ul>
          <h3>제목</h3><blockquote>인용</blockquote><hr><pre><code class="language-swift">  &lt;a&gt;
          **코드**</code></pre></details></li></ul><p>다음</p>
        """
        #expect(NotionHTMLImport.source(html) == "+ 계획 & 메모\n\t[x] 초안\n\t\t- 자료\n\t### 제목\n\t> 인용\n\t---\n\t```swift\n\t  <a>\n\t  **코드**\n\t```\n다음")
    }

    @Test func headingToggleVariantsAndSiblings() {
        for (level, size) in [(1, "1.875em"), (2, "1.5em"), (3, "1.25em")] {
            for title in ["<summary style='font-size: \(size);'>글</summary>", "<summary><h\(level)>글</h\(level)></summary>"] {
                let html = "<details open>\(title)<div class='indented'><details><summary>하위</summary>내용</details></div></details><p>끝</p>"
                #expect(NotionHTMLImport.source(html) == "+ " + String(repeating: "#", count: level) + " 글\n\t+ 하위\n\t\t내용\n끝")
            }
        }
    }

    @Test func nativeCheckboxesAndOmittedListEndTags() {
        let html = """
        <ul><li><label><input type=checkbox checked> A</label><ol><li>B<li>C</ol>
        <li><p><input type=checkbox> D</p>
        <li><div class="checkbox checkbox-off"></div> <span class="to-do-children-unchecked">E</span></ul>
        """
        #expect(NotionHTMLImport.source(html) == "[x] A\n\t- B\n\t- C\n[ ] D\n[ ] E")
    }

    @Test func inlineStylesLinksEntitiesAndBreaks() {
        let html = """
        <details><summary>&#x1F4DD;</summary><p><b>굵게</b> <del>취소</del> <u>밑줄</u><br>
        <a href="https://x.example/?a=1&amp;b=2">링크</a> <code>*글*</code> <a href="file:///tmp/x">글</a></p></details>
        """
        let source = NotionHTMLImport.source(html)
        #expect(source == "+ 📝\n\t**굵게** ~~취소~~ <u>밑줄</u>\\\n\t [링크](https://x.example/?a=1&b=2) `*글*` 글")
    }

    @Test func roundTripEveryInkAndItsChildren() {
        for ink in InkColor.palette {
            let source = "+ ## 제목" + ink.comment + "\n\t[x] ==강조=={" + ink.suffix + "}" + ink.comment + "\n\t\t- 자식"
            let html = CopyExport(source: source).html(highlightColors: [ink.id: "#123456"])
            #expect(html.contains("style=\"\(ink.foreground ? "color" : "background-color"):#123456\""))
            #expect(NotionHTMLImport.source(html) == source)
        }
    }

    @Test func overlappingNotionColorsKeepTheOuterColorAndInnerFormatting() {
        let html = #"<h3 class="block-color-pink"><mark class="highlight-pink"><mark class="highlight-yellow_background"><strong>제목</strong></mark></mark></h3>"#
        #expect(NotionHTMLImport.source(html) == "### ==**제목**=={분홍 글자} <!-- 분홍 글자 -->")
    }

    @MainActor @Test func readsTheRichestSupportedFlavor() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("https://example.com", forType: .URL)
        #expect(EditorController.source(from: board)?.text == "https://example.com")
        board.setString("일반 글자", forType: .string)
        board.setData(Data("<p>웹 글자</p>".utf8), forType: .html)
        #expect(EditorController.source(from: board)?.text == "일반 글자")
        board.setData(Data("<details><summary>제목</summary>자식</details>".utf8), forType: .html)
        #expect(EditorController.source(from: board)?.text == "+ 제목\n\t자식")
        board.setString("+ Float 원문", forType: .floatingNotesMarkdown)
        #expect(EditorController.source(from: board)?.text == "+ Float 원문")
    }

    @Test func fallsBackForUnrecognizedOrUnsupportedContent() {
        for html in ["<p>일반 웹 페이지</p>", "<h2>제목</h2><ul><li>보통 목록</li></ul>",
                     "<p>checkbox-on</p><!-- <details> -->", "<details><p>요약 없음</p></details>",
                     "<details><summary>목록</summary><table><tr><td>값</td></tr></table></details>",
                     "<p>보존할 앞부분</p><details><summary>끝</summary><img src='file:///example'></details>"] {
            #expect(NotionHTMLImport.source(html) == nil)
        }
    }
}
