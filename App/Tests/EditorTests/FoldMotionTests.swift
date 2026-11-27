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
        let expandedHeight = h.editor.contentHeight
        h.caret(atEndOfLine: 1)
        h.perform(.toggleDone)
        #expect(h.editor.foldedLines == [0])
        #expect(FoldState.hiddenLines(h.document, folded: h.editor.foldedLines) == [2])
        #expect(h.controller.currentKeys()[2].isCollapsed)
        #expect(!h.controller.currentKeys()[1].isCollapsed)
        #expect(h.heights.last == h.editor.contentHeight && h.editor.contentHeight < expandedHeight)
        now += h.theme.motion.chevronRotation / 2
        h.controller.advanceFoldMotion()
        let halfway = try #require(h.controller.foldDrawing.openness[0])
        #expect(halfway > 0 && halfway < 1)
        h.perform(.unfold)
        #expect(h.editor.foldedLines.isEmpty)
        #expect(h.controller.foldDrawing.openness[0] == halfway)
        #expect(!h.controller.currentKeys()[2].isCollapsed)
        #expect(h.heights.last == expandedHeight)
        now += h.theme.motion.chevronRotation
        #expect(!h.controller.advanceFoldMotion())
        #expect(h.controller.foldDrawing.openness[0] == nil)
        #expect(!h.editor.undoManager.canUndo)
    }

    @Test func synchronousFoldObserverDoesNotConsumeTheRotation() throws {
        let h = try EditorHarness("+ 토글\n\t자식\n뒤")
        var now = 1.0
        h.controller.foldAnimationsEnabled = { true }
        h.controller.foldClock = { now }
        let duration = h.theme.motion.chevronRotation
        h.editor.onFoldChange = { _ in now += duration }
        defer { h.controller.stopFoldMotion() }
        h.controller.toggleFold(line: 0)
        #expect(h.controller.advanceFoldMotion())
        #expect(h.controller.foldDrawing.openness[0] == 1)
        now += h.theme.motion.chevronRotation
        #expect(!h.controller.advanceFoldMotion())
        #expect(h.controller.currentKeys()[1].isCollapsed)
    }

    @Test func emptyToggleRotatesWhileItsHintAndHeightChangeImmediately() throws {
        let h = try EditorHarness("+ 토글")
        h.controller.foldAnimationsEnabled = { true }
        defer { h.controller.stopFoldMotion() }
        var changes: [Bool] = []
        h.editor.onContentHeightChange = { [weak h] _ in changes.append(h?.editor.isChangingUserFold == true) }
        let closedHeight = h.editor.contentHeight
        h.perform(.toggleDone)
        #expect(h.controller.foldDrawing.openness[0] == 0)
        #expect(h.controller.currentKeys()[0].showsEmptyToggleHint)
        #expect(h.editor.contentHeight > closedHeight)
        h.perform(.toggleDone)
        #expect(!h.controller.currentKeys()[0].showsEmptyToggleHint)
        #expect(h.editor.contentHeight == closedHeight)
        #expect(changes == [true, true])
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
