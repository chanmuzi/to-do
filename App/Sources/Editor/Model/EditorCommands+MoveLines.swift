import Foundation

nonisolated extension EditorCommands {
    enum MoveDirection: Sendable {
        case up, down
    }

    /// 줄 위로, 아래로 옮기기. 접힌 토글은 감춘 줄과 함께 한 덩어리로 움직인다.
    static func moveLines(
        _ doc: MarkdownDocument,
        selection: NSRange,
        folded: Set<Int>,
        direction: MoveDirection
    ) -> TextEdit? {
        let folded = FoldState.sanitized(folded, in: doc)
        let selected = doc.lineRange(for: selection)
        var first = selected.lowerBound
        var last = selected.upperBound
        if let root = FoldState.foldRoot(of: first, in: doc, folded: folded) { first = root }
        for index in first...last where folded.contains(index) {
            last = max(last, doc.lines[index].subtreeEnd - 1)
        }

        // 자리를 바꿀 이웃 덩어리.
        let neighbor: ClosedRange<Int>
        switch direction {
        case .up:
            guard first > 0 else { return nil }
            let above = first - 1
            neighbor = (FoldState.foldRoot(of: above, in: doc, folded: folded) ?? above)...above
        case .down:
            guard last < doc.lines.count - 1 else { return nil }
            let below = last + 1
            neighbor = below...(folded.contains(below) ? doc.lines[below].subtreeEnd - 1 : below)
        }

        func texts(_ lines: ClosedRange<Int>) -> [String] {
            lines.map { doc.string(in: doc.lines[$0].range) }
        }
        let block = first...last
        let blockTexts = texts(block)
        let neighborTexts = texts(neighbor)
        let regionStart = doc.lines[min(first, neighbor.lowerBound)].start
        let regionEnd = doc.lines[max(last, neighbor.upperBound)].end
        let ordered = direction == .up ? blockTexts + neighborTexts : neighborTexts + blockTexts
        let neighborLength = neighborTexts.joined(separator: "\n").utf16.count + 1
        let newBlockStart = direction == .up ? regionStart : regionStart + neighborLength
        let shift = newBlockStart - doc.lines[first].start

        let lineShift = direction == .up ? -neighbor.count : neighbor.count
        let neighborShift = direction == .up ? block.count : -block.count
        let foldedAfter = Set(folded.map { index in
            if block.contains(index) { return index + lineShift }
            if neighbor.contains(index) { return index + neighborShift }
            return index
        })

        return TextEdit(
            range: NSRange(location: regionStart, length: regionEnd - regionStart),
            replacement: ordered.joined(separator: "\n"),
            selection: NSRange(location: max(0, selection.location + shift), length: selection.length),
            foldedAfter: foldedAfter
        )
    }
}
