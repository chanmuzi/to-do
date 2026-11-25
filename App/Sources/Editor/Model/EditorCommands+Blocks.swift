import Foundation

nonisolated extension EditorCommands {
    /// 제목 1, 2, 3. 이미 그 제목이면 본문으로 되돌린다.
    static func toggleHeading(_ doc: MarkdownDocument, selection: NSRange, level: Int) -> TextEdit? {
        LinePrefixEdit.make(doc, lines: doc.lineRange(for: selection), selection: selection) { line in
            guard !line.kind.isCode else { return nil }
            let indent = doc.string(in: line.indentRange)
            let marker = line.kind.headingLevel == level ? "" : String(repeating: "#", count: level) + " "
            return .init(oldLength: line.prefixLength, new: indent + (line.kind.isToggle ? "+ " : "") + marker)
        }
    }

    /// 선택한 줄들의 글머리 목록 서식을 함께 전환한다.
    static func toggleBullet(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        let lines = doc.lineRange(for: selection)
        let targets = lines.filter { !doc.lines[$0].kind.isCode }
        let remove = targets.allSatisfy { doc.lines[$0].kind == .bullet }
        return LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            guard !line.kind.isCode, remove || line.kind != .bullet else { return nil }
            return .init(oldLength: line.prefixLength, new: doc.string(in: line.indentRange) + (remove ? "" : "- "))
        }
    }

    static func toggleTodo(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        let lines = doc.lineRange(for: selection)
        let targets = lines.filter { !doc.lines[$0].kind.isCode }
        let allTodo = !targets.isEmpty && targets.allSatisfy { isTodo(doc.lines[$0].kind) }
        return LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            guard !line.kind.isCode else { return nil }
            if isTodo(line.kind), !allTodo { return nil }
            let indent = doc.string(in: line.indentRange)
            return .init(oldLength: line.prefixLength, new: indent + (allTodo ? "" : "[ ] "))
        }
    }

    /// 완료 표시. 고른 줄 가운데 하나라도 미완료면 모두 완료로, 모두 완료면 모두 미완료로.
    static func toggleDone(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        toggleDone(doc, lines: doc.lineRange(for: selection), selection: selection)
    }

    static func toggleDone(_ doc: MarkdownDocument, lines: ClosedRange<Int>, selection: NSRange) -> TextEdit? {
        let states: [Bool] = lines.compactMap {
            if case .todo(let done) = doc.lines[$0].kind { done } else { nil }
        }
        guard !states.isEmpty else { return nil }
        let target = states.contains(false)
        return LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            guard isTodo(line.kind) else { return nil }
            let marker = doc.string(in: line.markerRange)
            let lead = marker.hasPrefix("[") ? "" : String(marker.prefix(2))
            return .init(
                oldLength: line.prefixLength,
                new: doc.string(in: line.indentRange) + lead + (target ? "[x] " : "[ ] ")
            )
        }
    }

    /// 코드 블록. 고른 줄을 ``` 로 감싼다. 이미 블록 안이면 ``` 줄을 지운다.
    static func toggleCodeBlock(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        let lines = doc.lineRange(for: selection)
        let first = doc.lines[lines.lowerBound]
        if let block = first.codeBlock {
            let isClosed = block.upperBound != block.lowerBound && doc.lines[block.upperBound].kind == .fenceClose
            let inner = (block.lowerBound + 1)..<(isClosed ? block.upperBound : block.upperBound + 1)
            let start = doc.lines[block.lowerBound].start
            let range = NSRange(location: start, length: doc.lines[block.upperBound].end - start)
            let body = inner.map { doc.string(in: doc.lines[$0].range) }.joined(separator: "\n")
            return TextEdit(range: range, replacement: body, selection: NSRange(location: start, length: 0))
        }
        let last = doc.lines[lines.upperBound]
        let range = NSRange(location: first.start, length: last.end - first.start)
        let body = doc.string(in: range)
        let selectionAfter = body.isEmpty
            ? NSRange(location: first.start + 4, length: 0)
            : NSRange(location: selection.location + 4, length: selection.length)
        return TextEdit(range: range, replacement: "```\n" + body + "\n```", selection: selectionAfter)
    }

    private static func isTodo(_ kind: LineKind) -> Bool {
        if case .todo = kind { true } else { false }
    }
}
