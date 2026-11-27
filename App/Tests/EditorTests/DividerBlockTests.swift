import AppKit
import Testing
@testable import Editor

@MainActor @Suite struct DividerBlockTests {
    @Test func syntaxStructureAndCopy() {
        let source = "본문\n----\n\n---\n+ 토글\n\t---\n\t\t안\n```\n---\n```"
        let doc = MarkdownDocument(source)
        #expect(doc.lines.map(\.kind) == [.paragraph, .divider, .paragraph, .divider, .toggle, .divider, .paragraph, .fenceOpen, .code, .fenceClose])
        #expect(doc.lines[5].subtreeEnd == 6)
        #expect(!ListStructure.hasParent(in: doc)[6])
        #expect(FoldState.hiddenLines(doc, folded: [4]).contains(5))
        let export = CopyExport(source: source)
        #expect(export.source == source)
        #expect(export.markdown == "본문\n\n---\n\n---\n- 토글\n\n\t---\n\t\t안\n```\n---\n```")
        #expect(export.html(highlightColors: [:]).components(separatedBy: "<hr>").count == 4)
    }

    @Test func standaloneDividerAndWholeDocumentDeletion() throws {
        let h = try EditorHarness("---")
        #expect(h.controller.blockSelection?.rows == 0...0)
        #expect(h.controller.caretRect() == nil)
        h.press(NSResponder.newline)
        #expect(h.marked == "---\n|")
        let source = "----\n본문\n---"
        h.editor.text = source
        h.view.selectAll(nil)
        h.press(NSResponder.backspace)
        #expect(h.editor.text.isEmpty)
        h.undo()
        #expect(h.editor.text == source)
    }

    @Test func externalTextCreatesDividerBlocksWithoutTheTypingTrigger() throws {
        let h = try EditorHarness()
        h.step { h.controller.pasteSource("문단\n----\n끝") }
        #expect(h.document.lines.map(\.kind) == [.paragraph, .divider, .paragraph])
        #expect(h.editor.text == "문단\n----\n끝")
    }

    @Test func triggerAndTwoUndoSteps() throws {
        let h = try EditorHarness.at("+ 부모\n\t--|\n\n뒤")
        h.type("-")
        #expect(h.marked == "+ 부모\n\t---\n\t|\n\n뒤")
        h.undo()
        #expect(h.marked == "+ 부모\n\t--\\-|\n\n뒤")
        #expect(h.document.lines[1].kind == .paragraph)
        #expect(h.document.lines[1].spans.map(\.kind) == [.escape])
        h.undo()
        #expect(h.marked == "+ 부모\n\t--|\n\n뒤")
    }

    @Test func compositionCommitsTheTriggerOnlyOnAnEmptyLine() throws {
        let h = try EditorHarness()
        h.mark("--")
        h.commit("---")
        #expect(h.marked == "---\n|")
        h.undo()
        #expect(h.document.lines.first?.kind == .paragraph)
        h.undo()
        #expect(h.editor.text == "--")
        let text = try EditorHarness.at("--|글")
        text.type("-")
        #expect(text.document.lines[0].kind == .paragraph)
    }

    @Test func arrowsSkipAndClickSelectsTheDivider() throws {
        let h = try EditorHarness.at("가|\n---\n나")
        h.press(NSResponder.right)
        #expect(h.marked == "가\n---\n|나")
        h.press(NSResponder.left)
        #expect(h.marked == "가|\n---\n나")
        h.press(NSResponder.down)
        #expect(h.document.lineIndex(at: h.editor.selectedRange.location) == 2)
        h.press(NSResponder.up)
        #expect(h.document.lineIndex(at: h.editor.selectedRange.location) == 0)
        let point = try #require(h.controller.textPoint(forLine: 1))
        #expect(h.controller.handleMouseDown(at: point))
        #expect(h.controller.blockSelection?.rows == 1...1)
        #expect(h.view.accessibilityValueDescription() == "구분선")
        #expect(try #require(h.controller.blockSelectionRects().first).height == 11)
        h.press(NSResponder.newline)
        #expect(h.marked == "가\n---\n|\n나")
    }

    @Test func adjacentDeletionSelectsBeforeRemoving() throws {
        for (before, key, selected) in [
            ("앞\n---\n|뒤", NSResponder.backspace, "앞\n---\n뒤"),
            ("앞\n---\n|\n뒤", NSResponder.backspace, "앞\n---\n뒤"),
            ("앞|\n---\n뒤", NSResponder.forwardDelete, "앞\n---\n뒤")
        ] {
            let h = try EditorHarness.at(before)
            h.press(key)
            #expect(h.editor.text == selected)
            #expect(h.controller.blockSelection?.rows == 1...1)
            h.press(key)
            #expect(h.editor.text == "앞\n뒤")
        }
    }

    @Test func menuInsertsAfterFoldedChildrenAndBlocksKeepTheirCommands() throws {
        let h = try EditorHarness.at("+ 부모|\n\t자식\n끝")
        h.editor.foldedLines = [0]
        h.step { h.view.insertMarkdownDivider(nil) }
        #expect(h.marked == "+ 부모\n\t자식\n---\n|\n끝")
        #expect(h.editor.foldedLines == [0])
        h.undo()
        #expect(h.marked == "+ 부모|\n\t자식\n끝")
        let d = try EditorHarness("- 부모\n---\n끝")
        d.controller.showBlocks(BlockSelection(anchor: 1, focus: 1))
        d.perform(.highlight)
        d.perform(.toggleDone)
        #expect(d.editor.text == "- 부모\n---\n끝")
        d.press(NSResponder.tab)
        #expect(d.editor.text == "- 부모\n\t---\n끝")
        d.press(NSResponder.backtab)
        d.perform(.duplicate)
        #expect(d.editor.text == "- 부모\n---\n---\n끝")
        d.perform(.moveLineDown)
        #expect(d.editor.text == "- 부모\n---\n끝\n---")
    }
}
