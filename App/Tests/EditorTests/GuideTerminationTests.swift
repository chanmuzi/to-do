import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct GuideTerminationTests {
    private func fragments(_ h: EditorHarness) -> [MarkdownLayoutFragment] {
        let manager = h.controller.layoutManager
        manager.ensureLayout(for: manager.documentRange)
        var result: [MarkdownLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? MarkdownLayoutFragment { result.append(fragment) }
            return true
        }
        return result
    }

    @Test func lastChildGuideStopsBeforeTheFollowingQuote() throws {
        let source = "- 부모\n\t- 첫째\n\t- 둘째\n> 인용\n> 이어지는 인용"
        let h = try EditorHarness(source)
        let layout = fragments(h)
        let firstChild = try #require(layout.first { $0.decoration?.guideLevels == [0] })
        let lastChild = try #require(layout.first { $0.decoration?.endingGuideLevels == [0] })
        let continuing = try #require(firstChild.guideRects.first)
        let ending = try #require(lastChild.guideRects.first)
        #expect(continuing.maxY == firstChild.layoutFragmentFrame.height)
        #expect(ending.maxY < lastChild.layoutFragmentFrame.height)
        #expect(ending.height > 0)
        #expect(layout.filter { $0.decoration?.quoteBar == true }.count == 2)
        #expect(Array(h.editor.text.utf8) == Array(source.utf8))
    }

    @Test func wrappedLastChildGuideReachesItsLastVisualLine() throws {
        let source = "- 부모\n\t- " + String(repeating: "긴 글자 ", count: 12) + "\n> 인용"
        let h = try EditorHarness(source, width: 180)
        let lastChild = try #require(fragments(h).first { $0.decoration?.endingGuideLevels == [0] })
        let lines = lastChild.textLineFragments.filter { $0.characterRange.length > 0 }
        #expect(lines.count > 1)
        let last = try #require(lines.last)
        let ending = try #require(lastChild.guideRects.first)
        #expect(ending.maxY > last.typographicBounds.minY)
        #expect(ending.maxY < lastChild.layoutFragmentFrame.height)
        #expect(Array(h.editor.text.utf8) == Array(source.utf8))
    }

    @Test func foldingAndAddingChildrenUpdateTheGuideEndpoint() {
        let doc = MarkdownDocument("- 부모\n\t+ 토글\n\t\t- 안쪽\n> 인용")
        let expanded = LinePresentation.keys(for: doc, folded: [])
        #expect(expanded[1].endingGuideLevels.isEmpty)
        #expect(expanded[2].endingGuideLevels == [0, 1])
        let folded = LinePresentation.keys(for: doc, folded: [1])
        #expect(folded[1].endingGuideLevels == [0])
        #expect(folded[2].isCollapsed)
        let extended = LinePresentation.keys(for: MarkdownDocument("- 부모\n\t+ 토글\n\t\t- 안쪽\n\t- 추가\n> 인용"), folded: [])
        #expect(extended[2].endingGuideLevels == [1])
        // 뒤에 줄을 추가했어도 이전 마지막 줄을 다시 그려 바깥 안내선을 잇는다.
        #expect(LinePresentation.changedLines(old: expanded, new: extended)?.lowerBound == 2)
    }
}
