import AppKit
import Testing
@testable import Editor

/// 선택이 줄어 커서가 될 때 감춘 줄 머리 안에 놓이지 않는다(이슈 #9).
@MainActor
@Suite struct PrefixSelectionTests {
    /// 퍼즈 씨앗 417의 108번째 차례를 줄인 것: 비어 있는 제목 줄을 ⇧←로 고르고 제목 2로 바꾼 뒤 ⇧←.
    @Test func shrinkingASelectionAfterALineKindCommandStopsAtTheVisibleStart() throws {
        let h = try EditorHarness.at("# |\n#=\n꼬리")
        h.press(NSResponder.shiftLeft)
        #expect(h.marked == "|# |\n#=\n꼬리")
        h.perform(.heading(2))
        #expect(h.marked == "|## |\n#=\n꼬리")
        h.press(NSResponder.shiftLeft)
        #expect(h.marked == "## |\n#=\n꼬리")
    }

    @Test(arguments: ["- |", "[ ] |", "\t|"])
    func shrinkingAWholePrefixSelectionLeavesTheCaretAfterThePrefix(_ start: String) throws {
        let h = try EditorHarness.at(start)
        let line = h.document.lines[0]
        h.place(at: line.start, length: line.caretStart - line.start)
        h.press(NSResponder.shiftLeft)
        #expect(h.editor.selectedRange == NSRange(location: line.caretStart, length: 0))
    }
}
