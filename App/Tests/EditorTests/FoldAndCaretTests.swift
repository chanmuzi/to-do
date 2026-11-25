import Foundation
import Testing
@testable import Editor

@Suite struct FoldStateTests {
    let doc = MarkdownDocument(DemoNote.text)

    @Test func foldedToggleHidesItsWholeSubtree() {
        #expect(FoldState.hiddenLines(doc, folded: [5]) == [6, 7, 8, 9])
        #expect(FoldState.hiddenLines(doc, folded: []) == [])
        #expect(FoldState.foldRoot(of: 8, in: doc, folded: [5]) == 5)
        #expect(FoldState.foldRoot(of: 5, in: doc, folded: [5]) == nil)
    }

    @Test func onlyTogglesCanBeFolded() {
        #expect(FoldState.sanitized([0, 5, 99, -1], in: doc) == [5])
    }

    @Test func foldFromInsideMovesTheCaretToTheTitle() throws {
        let inside = doc.lines[7].end
        let result = try #require(FoldState.fold(doc, selection: NSRange(location: inside, length: 0), folded: []))
        #expect(result.folded == [5])
        #expect(result.selection == NSRange(location: doc.lines[5].end, length: 0))
        // 토글 줄에서 접으면 커서는 그대로다.
        let onTitle = NSRange(location: doc.lines[5].contentStart, length: 0)
        #expect(FoldState.fold(doc, selection: onTitle, folded: [])?.selection == onTitle)
        #expect(FoldState.fold(doc, selection: NSRange(location: 0, length: 0), folded: []) == nil)
    }

    @Test func unfoldOnlyOnAFoldedToggle() {
        let onTitle = NSRange(location: doc.lines[5].end, length: 0)
        #expect(FoldState.unfold(doc, selection: onTitle, folded: [5]) == [])
        #expect(FoldState.unfold(doc, selection: onTitle, folded: []) == nil)
    }

    @Test func foldedLinesFollowEditsAboveAndBelow() {
        func remap(_ edit: TextEdit) -> Set<Int> {
            let new = MarkdownDocument(edit.applied(to: doc.text))
            let delta = edit.replacement.utf16.count - edit.range.length
            let edited = NSRange(location: edit.range.location, length: edit.replacement.utf16.count)
            return FoldState.remapped([5], old: doc, new: new, editedRange: edited, delta: delta)
        }
        // 위에 줄을 더하면 한 줄 밀린다.
        #expect(remap(.insert("새 줄\n", replacing: NSRange(location: 0, length: 0))) == [6])
        // 위의 줄을 지우면 한 줄 당겨진다.
        #expect(remap(TextEdit(range: doc.lines[0].fullRange, replacement: "", selection: NSRange())) == [4])
        // 아래를 고치면 그대로다.
        #expect(remap(.insert("!", replacing: NSRange(location: doc.length, length: 0))) == [5])
        // 토글 제목을 고쳐도 접힌 채다.
        #expect(remap(.insert("!", replacing: NSRange(location: doc.lines[5].end, length: 0))) == [5])
        // 토글 줄 맨 앞에서 줄을 나누면 토글을 따라간다.
        #expect(remap(.insert("\n", replacing: NSRange(location: doc.lines[5].start, length: 0))) == [6])
        // 토글이 아니게 되면 접힘을 버린다.
        #expect(remap(TextEdit(range: doc.lines[5].markerRange, replacement: "", selection: NSRange())) == [])
    }
}

@Suite struct CaretSnappingTests {
    let doc = MarkdownDocument(DemoNote.text)

    private func snap(from old: Int, to new: Int, folded: Set<Int> = []) -> Int {
        CaretSnapping.snap(
            old: NSRange(location: old, length: 0),
            new: NSRange(location: new, length: 0),
            in: doc,
            folded: folded
        ).location
    }

    @Test func caretNeverLandsInsideAHiddenLineMarker() {
        let line = doc.lines[2] // "\t[ ] 포커스…"
        #expect(line.contentStart == line.start + 5)
        // 줄 맨 앞을 누르면 글자 시작으로.
        #expect(snap(from: 0, to: line.start) == line.contentStart)
        #expect(snap(from: 0, to: line.start + 3) == line.contentStart)
        // ⌘← 처럼 같은 줄 안에서 앞으로 가도 글자 시작에서 멈춘다.
        #expect(snap(from: line.end, to: line.start) == line.contentStart)
    }

    @Test func leftFromContentStartGoesToThePreviousLineEnd() {
        let line = doc.lines[2]
        #expect(snap(from: line.contentStart, to: line.contentStart - 1) == doc.lines[1].end)
        // 첫 줄에서는 갈 곳이 없으니 제자리.
        #expect(snap(from: doc.lines[0].contentStart, to: doc.lines[0].contentStart - 1) == doc.lines[0].contentStart)
    }

    @Test func positionsInsideTheTextAreUntouched() {
        let line = doc.lines[2]
        #expect(snap(from: 0, to: line.contentStart + 2) == line.contentStart + 2)
        #expect(snap(from: 0, to: line.end) == line.end)
    }

    @Test func selectionTakesTheHiddenMarkerWholeOrNotAtAll() {
        let line = doc.lines[2] // "\t[ ] 포커스…", 줄 머리 5글자
        func snap(_ old: NSRange, _ new: NSRange) -> NSRange {
            CaretSnapping.snap(old: old, new: new, in: doc, folded: [])
        }
        // 글자 시작에서 ⇧← : 줄 머리 전체가 선택에 들어간다.
        let fromContent = NSRange(location: line.contentStart, length: 0)
        #expect(snap(fromContent, NSRange(location: line.contentStart - 1, length: 1)) == NSRange(location: line.start, length: 5))
        // 윗줄 끝에서 ⇧→ 두 번: 줄바꿈, 그다음 줄 머리 전체.
        let previousEnd = doc.lines[1].end
        let newline = NSRange(location: previousEnd, length: 1)
        #expect(snap(NSRange(location: previousEnd, length: 0), newline) == newline)
        #expect(snap(newline, NSRange(location: previousEnd, length: 2)) == NSRange(location: previousEnd, length: 6))
        // 다시 ⇧← 하면 줄 머리가 통째로 빠진다.
        #expect(snap(NSRange(location: previousEnd, length: 6), NSRange(location: previousEnd, length: 5)) == newline)
        // 줄 머리에 걸리지 않는 선택은 그대로다.
        let plain = NSRange(location: 0, length: 10)
        #expect(snap(NSRange(), plain) == plain)
    }

    @Test func caretSkipsFoldedLines() {
        let title = doc.lines[5]
        let tail = MarkdownDocument(DemoNote.text + "\n끝")
        // 접힌 줄로 들어가려 하면 제목 끝에 머문다(뒤에 줄이 없을 때).
        #expect(snap(from: title.end, to: title.end + 1, folded: [5]) == title.end)
        // 뒤에 줄이 있으면 접힌 덩어리를 건너뛴다.
        let forward = CaretSnapping.snap(
            old: NSRange(location: title.end, length: 0),
            new: NSRange(location: title.end + 1, length: 0),
            in: tail,
            folded: [5]
        )
        #expect(forward.location == tail.lines[10].start)
        // 아래에서 위로 올라오면 제목 끝으로.
        let backward = CaretSnapping.snap(
            old: NSRange(location: tail.lines[10].start, length: 0),
            new: NSRange(location: tail.lines[10].start - 1, length: 0),
            in: tail,
            folded: [5]
        )
        #expect(backward.location == title.end)
    }

    @Test func headingMarkerIsNeverReachable() {
        // 제목의 `#`도 목록 기호처럼 늘 감춘다. 커서는 글자 시작보다 앞에 놓이지 않는다.
        let heading = MarkdownDocument("앞\n\t# 제목")
        let line = heading.lines[1]
        #expect(line.caretStart == line.contentStart)
        func snap(from old: Int, to new: Int) -> Int {
            CaretSnapping.snap(old: NSRange(location: old, length: 0), new: NSRange(location: new, length: 0), in: heading, folded: []).location
        }
        #expect(snap(from: line.end, to: line.start + 1) == line.contentStart)
        #expect(snap(from: line.end, to: line.start) == line.contentStart)
        #expect(snap(from: line.contentStart, to: line.contentStart - 1) == heading.lines[0].end)
    }
}

@Suite struct LinePresentationTests {
    let doc = MarkdownDocument(DemoNote.text)

    @Test func foldedSubtreeIsCollapsed() {
        let keys = LinePresentation.keys(for: doc, folded: [5])
        #expect(keys[5].isFolded)
        #expect(keys.indices.filter { keys[$0].isCollapsed } == [6, 7, 8, 9])
    }

    @Test func codeBlockKnowsItsTopAndBottom() {
        let code = MarkdownDocument("앞\n```\ncode\n```\n뒤")
        let keys = LinePresentation.keys(for: code, folded: [])
        #expect(keys[1].isCodeTop && keys[3].isCodeBottom && !keys[2].isCodeTop && !keys[2].isCodeBottom)
        #expect(!keys[0].isCodeTop && !keys[4].isCodeBottom)
    }

    @Test func changedLinesIsTheMiddleDifference() {
        let before = LinePresentation.keys(for: doc, folded: [])
        let after = LinePresentation.keys(for: doc, folded: [], hoveredLink: (line: 3, offset: 0))
        #expect(LinePresentation.changedLines(old: before, new: after) == 3..<4)
        #expect(LinePresentation.changedLines(old: before, new: before) == nil)
        // 줄 수가 달라도 앞뒤의 같은 부분은 뺀다.
        let longer = MarkdownDocument("새 줄\n" + DemoNote.text)
        let shifted = LinePresentation.keys(for: longer, folded: [])
        #expect(LinePresentation.changedLines(old: before, new: shifted) == 0..<2)
    }
}
