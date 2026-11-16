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
        var block = FoldState.expanded(doc.lineRange(for: selection), in: doc, folded: folded)
        // 코드 블록의 ``` 줄을 넘어 옮기지 않는다. 블록 안의 줄은 블록 안에서만 움직이고, 그 밖에는 블록이
        // 통째로 한 덩어리다. 넘겨 옮기면 줄이 없는 블록이나 짝 잃은 ``` 줄이 남는다.
        let inside = doc.lines[block.lowerBound].codeBlock.flatMap { code in
            block.allSatisfy { doc.lines[$0].kind == .code && doc.lines[$0].codeBlock == code } ? code : nil
        }
        if inside == nil {
            for index in block {
                guard let code = doc.lines[index].codeBlock else { continue }
                guard doc.lines[code.upperBound].kind == .fenceClose, code.count > 1 else { return nil }
                block = min(block.lowerBound, code.lowerBound)...max(block.upperBound, code.upperBound)
            }
        }
        let first = block.lowerBound
        let last = block.upperBound

        // 자리를 바꿀 이웃 덩어리.
        let neighbor: ClosedRange<Int>
        switch direction {
        case .up:
            guard first > 0 else { return nil }
            let above = first - 1
            if inside != nil {
                guard doc.lines[above].kind == .code else { return nil }
                neighbor = above...above
            } else if let code = doc.lines[above].codeBlock {
                guard doc.lines[code.upperBound].kind == .fenceClose, code.count > 1 else { return nil }
                neighbor = code
            } else {
                neighbor = (FoldState.foldRoot(of: above, in: doc, folded: folded) ?? above)...above
            }
        case .down:
            guard last < doc.lines.count - 1 else { return nil }
            let below = last + 1
            if inside != nil {
                guard doc.lines[below].kind == .code else { return nil }
                neighbor = below...below
            } else if let code = doc.lines[below].codeBlock {
                guard doc.lines[code.upperBound].kind == .fenceClose, code.count > 1 else { return nil }
                neighbor = code
            } else {
                neighbor = below...(folded.contains(below) ? doc.lines[below].subtreeEnd - 1 : below)
            }
        }

        func texts(_ lines: ClosedRange<Int>) -> [String] {
            lines.map { doc.string(in: doc.lines[$0].range) }
        }
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
            foldedAfter: foldedAfter,
            includesHiddenLines: true
        )
    }
}
