import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct FoldMotionTests {
    @Test(arguments: ["+ 토글", "+ ## 제목"])
    func reversingKeepsThePresentedFrameAndChangesLogicalStateImmediately(_ title: String) throws {
        let h = try EditorHarness("\(title)\\\n이어짐\n\t안쪽\n뒤")
        var now = 1.0
        h.controller.foldAnimationsEnabled = { true }
        h.controller.foldClock = { now }
        h.caret(atEndOfLine: 1)
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines == [0])
        #expect(FoldState.hiddenLines(h.document, folded: h.editor.foldedLines) == [2])
        #expect(!h.controller.currentKeys()[2].isCollapsed)
        now += h.theme.motion.duration / 2
        h.controller.advanceFoldMotion()
        let halfway = h.controller.foldDrawing.opacity(at: 2)
        #expect(halfway > 0 && halfway < 1)
        #expect(h.controller.foldDrawing.opacity(at: 1) == 1)
        h.perform(.unfold)
        #expect(h.editor.foldedLines.isEmpty)
        #expect(h.controller.foldDrawing.opacity(at: 2) == halfway)
        now += h.theme.motion.duration
        #expect(!h.controller.advanceFoldMotion())
        #expect(h.controller.foldDrawing.opacity(at: 2) == 1)
        #expect(!h.editor.undoManager.canUndo)
    }

    @Test func reducedMotionCollapsesSynchronouslyInBothModes() throws {
        let h = try EditorHarness("+ ## 제목\n\t자식")
        h.controller.foldAnimationsEnabled = { false }
        h.controller.selectBlocks()
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines == [0] && h.controller.currentKeys()[1].isCollapsed)
        #expect(h.controller.foldTask == nil)
        h.perform(.toggleDone)
        #expect(!h.controller.currentKeys()[1].isCollapsed)
        h.controller.clearBlocks()
        let point = try #require(h.controller.gutterPoint(forLine: 0))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(h.controller.currentKeys()[1].isCollapsed)
    }
}
