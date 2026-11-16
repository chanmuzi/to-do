import Foundation
import Testing
@testable import Editor

@Suite struct MarkdownDocumentTests {
    @Test func keepsSourceTextExactly() {
        let source = "# 제목\r\n[ ] 할 일\n\t- 하위\n\n```\ncode\n```\n끝"
        let doc = MarkdownDocument(source)
        #expect(doc.text == source)
        // 줄 범위를 이으면 원문 전체가 된다(빠지거나 겹치는 글자가 없다).
        var position = 0
        for line in doc.lines {
            #expect(line.fullRange.location == position)
            position = NSMaxRange(line.fullRange)
        }
        #expect(position == source.utf16.count)
    }

    @Test func lineBoundariesMatchParagraphSeparators() {
        let doc = MarkdownDocument("a\r\nb\rc\nd\u{2029}e")
        #expect(doc.lines.map { doc.string(in: $0.range) } == ["a", "b", "c", "d", "e"])
        #expect(doc.lines.map { $0.fullRange.length - $0.range.length } == [2, 1, 1, 1, 0])
    }

    @Test func trailingNewlineAddsAnEmptyLastLine() {
        #expect(MarkdownDocument("a\n").lines.count == 2)
        #expect(MarkdownDocument("").lines.count == 1)
        #expect(MarkdownDocument("a").lines.count == 1)
    }

    @Test func classifiesEveryBlockKind() {
        let doc = MarkdownDocument("""
        # 하나
        ## 둘
        ### 셋
        #### 넷은 제목이 아니다
        #붙여 쓰면 본문
        본문
        [ ] 할 일
        [x] 끝낸 일
        [] 빈 대괄호
        - [ ] 표준 문법
        - [X] 표준 완료
        - 글머리표
        * 별표 글머리표
        > 토글
        -붙여 쓰면 본문
        """)
        #expect(doc.lines.map(\.kind) == [
            .heading(1), .heading(2), .heading(3), .paragraph, .paragraph, .paragraph,
            .todo(done: false), .todo(done: true), .todo(done: false),
            .todo(done: false), .todo(done: true),
            .bullet, .bullet, .toggle, .paragraph,
        ])
        #expect(doc.lines.map(\.markerLength) == [2, 3, 4, 0, 0, 0, 4, 4, 3, 6, 6, 2, 2, 2, 0])
    }

    @Test func todoWithoutTrailingSpaceAtLineEnd() {
        #expect(MarkdownDocument("[ ]").lines[0].kind == .todo(done: false))
        #expect(MarkdownDocument("[x]").lines[0].kind == .todo(done: true))
        // `[]`는 Space를 쳐야 투두가 된다.
        #expect(MarkdownDocument("[]").lines[0].kind == .paragraph)
        #expect(MarkdownDocument("[ ]글자").lines[0].kind == .paragraph)
    }

    @Test func indentationLevels() {
        let doc = MarkdownDocument("- 0\n\t- 1\n\t\t- 2\n  - 공백 둘\n    - 공백 넷\n\t  - 섞음")
        #expect(doc.lines.map(\.level) == [0, 1, 2, 1, 2, 2])
        #expect(doc.lines.map(\.indentLength) == [0, 1, 2, 2, 4, 3])
        #expect(doc.lines[2].contentStart == doc.lines[2].start + 4)
    }

    @Test func codeBlockLinesAreNotParsedAsMarkdown() {
        let doc = MarkdownDocument("앞\n```swift\n# 제목 아님\n- **굵게 아님**\n```\n뒤")
        #expect(doc.lines.map(\.kind) == [.paragraph, .fenceOpen, .code, .code, .fenceClose, .paragraph])
        #expect(doc.lines[3].spans.isEmpty)
        #expect(doc.lines[1].codeBlock == 1...4)
        #expect(doc.lines[4].codeBlock == 1...4)
        #expect(doc.lines[0].codeBlock == nil)
        #expect(doc.lines[5].codeBlock == nil)
    }

    @Test func unterminatedCodeBlockRunsToTheEnd() {
        let doc = MarkdownDocument("```\na\nb")
        #expect(doc.lines.map(\.kind) == [.fenceOpen, .code, .code])
        #expect(doc.lines[2].codeBlock == 0...2)
    }

    @Test func toggleCountsDirectChildrenOnly() {
        let doc = MarkdownDocument(DemoNote.text)
        let toggle = doc.lines[5]
        #expect(toggle.kind == .toggle)
        #expect(toggle.childCount == 3)
        #expect(toggle.subtreeEnd == 10)
        #expect(doc.lines[1].subtreeEnd == 4)
        #expect(doc.lines[0].subtreeEnd == 1)
    }

    @Test func lineLookup() {
        let doc = MarkdownDocument("ab\ncd\n")
        #expect(doc.lineIndex(at: 0) == 0)
        #expect(doc.lineIndex(at: 2) == 0)
        #expect(doc.lineIndex(at: 3) == 1)
        #expect(doc.lineIndex(at: 6) == 2)
        #expect(doc.lineRange(for: NSRange(location: 0, length: 3)) == 0...0)
        #expect(doc.lineRange(for: NSRange(location: 0, length: 4)) == 0...1)
        #expect(doc.lineRange(for: NSRange(location: 3, length: 0)) == 1...1)
    }
}

/// 화면 2 맨 위 노트의 원문. 여러 테스트가 함께 쓴다.
enum DemoNote {
    static let text = """
    [x] 스탠드업 회의록 공유
    [ ] **PR #482** 리뷰
    \t[ ] 포커스 전환 애니메이션 확인
    \t- 리뷰 코멘트 2건에 답글
    [ ] ==배포 체크리스트 확인==
    > 지난주에서 넘어온 것
    \t[ ] **온보딩 문서** 초안 마무리
    \t[ ] `feature/quick-capture` 브랜치 정리
    \t\t- 리베이스한 뒤 푸시
    \t[x] 주간 리포트 제출
    """
}
