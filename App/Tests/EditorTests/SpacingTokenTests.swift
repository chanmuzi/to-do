import AppKit
import Testing
import Theme
@testable import Editor

/// 왼쪽 칸과 줄 높이는 토큰에서 오고, 테마의 덮어쓰기로 바꾸면 떠 있는 편집기에 바로 반영된다.
@MainActor
@Suite struct SpacingTokenTests {
    private func paragraphStyle(_ h: EditorHarness, line: Int) throws -> NSParagraphStyle {
        try #require(try h.display(line: line).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    }

    @Test func defaultsComeFromTheTokens() throws {
        let h = try EditorHarness("[ ] 할 일\n\t- 하위\n본문")
        #expect(h.theme.component(.gutter) == 19)
        #expect(h.theme.component(.indent) == 19)
        #expect(h.theme.lineHeight(.body) == 22)
        #expect(try paragraphStyle(h, line: 0).headIndent == 19)
        #expect(try paragraphStyle(h, line: 1).headIndent == 38)
        #expect(try paragraphStyle(h, line: 2).minimumLineHeight == 22)
    }

    @Test func overridesUpdateAnOpenEditorLive() throws {
        let h = try EditorHarness("[ ] 할 일\n\t- 하위\n> 인용\n본문")
        let before = h.editor.contentHeight
        try h.theme.setOverrides(ThemeOverrides(values: [
            "component.gutter": "26px", "component.indent": "30px", "type.lh-body": "24px", "component.quote-pad": "20px",
        ]))
        #expect(try paragraphStyle(h, line: 0).headIndent == 26)
        #expect(try paragraphStyle(h, line: 1).headIndent == 56)
        #expect(try paragraphStyle(h, line: 2).headIndent == 20)
        #expect(try paragraphStyle(h, line: 3).minimumLineHeight == 24)
        #expect(h.editor.contentHeight > before)
        // 왼쪽 칸 그림도 새 칸에 놓인다.
        let decoration = try #require(try h.display(line: 1).attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration)
        #expect(decoration.gutterX == 30)
        // 되돌리면 기본값으로 돌아온다.
        try h.theme.setOverrides(ThemeOverrides())
        #expect(try paragraphStyle(h, line: 0).headIndent == 19)
    }

    @Test func decorationMetricsFollowLiveTokenOverrides() throws {
        let h = try EditorHarness("본문\n## 제목\n- 목록")
        #expect(h.controller.style.metrics.bulletDot == h.theme.component(.editorBulletDot))
        try h.theme.setOverrides(ThemeOverrides(values: [
            "component.editor-bullet-dot": "7px",
            "component.editor-heading2-before": "10px",
        ]))
        #expect(h.controller.style.metrics.bulletDot == 7)
        #expect(try paragraphStyle(h, line: 1).paragraphSpacingBefore == 10)
        try h.theme.setOverrides(ThemeOverrides())
        #expect(h.controller.style.metrics.bulletDot == 5)
        #expect(try paragraphStyle(h, line: 1).paragraphSpacingBefore == 6)
    }

    /// 체크박스와 글머리표는 줄이 넘어간 문단에서도 첫 줄의 세로 가운데에 놓인다.
    @Test func gutterGlyphsCenterOnTheFirstLineOfAWrappedParagraph() throws {
        let h = try EditorHarness("[ ] " + String(repeating: "길게 이어지는 할 일 ", count: 8) + "\n- 짧은 항목", width: 220)
        let wrapped = try #require(h.controller.gutterPoint(forLine: 0))
        let first = try #require(h.controller.textPoint(forLine: 0))
        #expect(abs(wrapped.y - first.y) <= 0.5)
        let single = try #require(h.controller.textPoint(forLine: 1))
        #expect(single.y - first.y > h.theme.lineHeight(.body) * 2)
    }
}
