import Foundation

nonisolated extension EditorCommands {
    static func lineBreak(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> TextEdit {
        let line = doc.line(at: selection.location)
        if line.kind == .code { return newlineInCode(doc, line: line, selection: selection) }
        guard !line.kind.isCode else { return newline(doc, selection: selection, folded: folded) }
        let range = normalized(doc, selection, replacement: "\n")
        // 홀수 번째 역슬래시가 개행 표지가 되도록, 커서 앞의 리터럴 역슬래시는 이스케이프한다.
        var start = range.location
        while start > line.contentStart, doc.units[start - 1] == 0x5C { start -= 1 }
        let marker = (range.location - start).isMultiple(of: 2) ? "\\" : "\\\\"
        return insert(doc, marker + "\n" + doc.string(in: line.indentRange), replacing: range)
    }

    /// Return. 목록은 같은 기호로 이어 가고, 빈 항목에서는 기호를 지우거나 한 단계 내어 쓴다.
    /// 서식 구간 한가운데에서 누르면 구간을 줄바꿈 앞에서 닫고 다음 줄에서 다시 연다.
    static func newline(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit {
        let row = doc.lineIndex(at: selection.location)
        let line = doc.lines[row]
        if selection.length == 0, line.continuationOf == nil, !line.kind.isCode,
           line.isVisualStart(selection.location),
           doc.blockLines(at: row).contains(where: { doc.lines[$0].contentRange.length > 0 }) {
            let prefix = doc.string(in: line.indentRange) + nextMarker(doc, line)
            return TextEdit(range: NSRange(location: line.start, length: 0), replacement: prefix + "\n",
                            selection: NSRange(location: selection.location + prefix.utf16.count + 1, length: 0))
        }
        let edit = splitLine(doc, selection: selection, folded: folded)
        return keepingInkOnSplit(doc, selection: selection, edit: edit)
    }

    private static func nextMarker(_ doc: MarkdownDocument, _ line: MarkdownLine) -> String {
        let marker = doc.string(in: line.markerRange)
        if case .todo = line.kind { return marker.hasPrefix("[") ? "[ ] " : String(marker.prefix(2)) + "[ ] " }
        return line.kind.isListItem ? marker : ""
    }

    private static func splitLine(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> TextEdit {
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        let indent = doc.string(in: line.indentRange)
        let isCaret = selection.length == 0
        // 커서 뒤의 공백은 줄바꿈과 함께 지운다. 남겨 두면 새 줄의 맨 앞에서 감춘 들여쓰기가 된다.
        var selection = selection
        if !line.kind.isCode, selection.location >= line.contentStart {
            let endLine = doc.line(at: NSMaxRange(selection))
            var upper = NSMaxRange(selection)
            while upper < endLine.contentEnd, doc.units[upper] == 0x20 || doc.units[upper] == 0x09 { upper += 1 }
            selection.length = upper - selection.location
        }

        if let owner = line.continuationOf {
            let first = doc.lines[owner]
            if isCaret, folded.contains(owner), !line.isVisualStart(selection.location),
               first.subtreeEnd > doc.blockLines(at: owner).upperBound + 1 {
                return splitFoldedToggle(doc, index: index, selection: selection, folded: folded)
            }
            let marker = first.kind.headingLevel != nil ? doc.string(in: first.markerRange) : nextMarker(doc, first)
            return insert(doc, "\n" + indent + marker, replacing: selection)
        }
        switch line.kind {
        case .code:
            if isCaret, let exit = leavingCodeBlock(doc, lineIndex: index) { return exit }
            return newlineInCode(doc, line: line, selection: selection)

        case .fenceOpen, .fenceClose:
            // 줄이 없는 블록의 커서 자리: 빈 코드 줄 둘을 만들고 둘째 줄로 간다.
            if isCaret, let block = emptyBlock(doc, caretAt: selection.location) {
                return insertingIntoEmptyBlock(doc, block, "\n")
            }
            // ``` 줄에는 커서가 놓이지 않는다. 놓였더라도 줄만 나눈다.
            return .insert("\n" + (line.kind == .fenceOpen ? indent : ""), replacing: selection)

        case .divider:
            return .insert("\n" + indent, replacing: NSRange(location: line.end, length: 0))

        case .heading:
            return insert(doc, "\n" + (selection.location >= line.contentStart ? indent : ""), replacing: selection)

        case .paragraph:
            if isCaret, !line.hasHardBreak, line.contentRange.length == 0, line.indentLength > 0 {
                return removingLastIndentUnit(doc, line: line)
            }
            return insert(doc, "\n" + indent, replacing: selection)

        case .todo, .bullet, .toggle, .toggleHeading, .quote:
            // 빈 항목(빈 인용문 줄 포함)에서는 기호를 지우거나 한 단계 내어 쓴다. 글이 있는 인용문은 본문으로 나온다.
            if isCaret, !line.hasHardBreak, line.contentRange.length == 0 {
                if line.indentLength > 0, let edit = outdent(doc, selection: selection, folded: folded) { return edit }
                return TextEdit(range: line.markerRange, replacement: "", selection: NSRange(location: line.start + line.indentLength, length: 0))
            }
            let marker = nextMarker(doc, line)
            let blockEnd = doc.blockLines(at: index).upperBound
            if line.kind.isToggle, line.subtreeEnd > blockEnd + 1 {
                if isCaret, folded.contains(index) {
                    return splitFoldedToggle(doc, index: index, selection: selection, folded: folded)
                }
                return insert(doc, "\n" + indent + "\t", replacing: selection)
            }
            return insert(doc, "\n" + indent + marker, replacing: selection)
        }
    }

    /// 먼저 제목을 서식 경계에서 나누고, 두 조각 사이에 감춰진 하위 원문을 그대로 끼운다.
    private static func splitFoldedToggle(_ doc: MarkdownDocument, index: Int, selection: NSRange, folded: Set<Int>) -> TextEdit {
        let line = doc.lines[index]
        let blockEnd = doc.blockLines(at: index).upperBound
        var range = selection
        while range.location > line.contentStart, doc.units[range.location - 1] == 0x20 {
            range.location -= 1
            range.length += 1
        }
        let owner = doc.lines[line.continuationOf ?? index]
        let split = insert(doc, "\n" + doc.string(in: owner.prefixRange), replacing: range)
        var edit = keepingInkOnSplit(doc, selection: range, edit: split)
        let children = NSRange(location: doc.lines[blockEnd].end, length: doc.lines[owner.subtreeEnd - 1].end - doc.lines[blockEnd].end)
        let tailStart = NSMaxRange(edit.range)
        edit.replacement += doc.string(in: NSRange(location: tailStart, length: children.location - tailStart))
        if let boundary = edit.replacement.firstIndex(of: "\n") {
            edit.replacement.insert(contentsOf: doc.string(in: children), at: boundary)
        }
        edit.range.length = NSMaxRange(children) - edit.range.location
        edit.selection.location += children.length
        edit.foldedAfter = Set(folded.map { row in
            if row >= owner.subtreeEnd { return row + 1 }
            return row > blockEnd ? row - (blockEnd - index) : row
        })
        edit.includesHiddenLines = true
        return edit
    }

    private static func newlineInCode(_ doc: MarkdownDocument, line: MarkdownLine, selection: NSRange) -> TextEdit {
        // 코드의 들여쓰기(커서 앞까지)를 다음 줄로 가져간다.
        var end = line.start
        while end < min(line.end, selection.location), doc.units[end] == 0x09 || doc.units[end] == 0x20 { end += 1 }
        return .insert("\n" + doc.string(in: NSRange(location: line.start, length: end - line.start)), replacing: selection)
    }

    /// 코드 블록의 빈 마지막 줄에서 Return: 그 빈 줄을 지우고 블록 아래에 새 문단을 연다.
    /// 줄이 하나뿐인 블록에서는 나가지 않는다(줄이 없는 블록이 남지 않게).
    /// 닫히지 않은 블록(문서 끝까지 이어진다)은 닫는 줄을 넣어 닫는다.
    static func leavingCodeBlock(_ doc: MarkdownDocument, lineIndex index: Int) -> TextEdit? {
        let line = doc.lines[index]
        guard line.kind == .code, let block = line.codeBlock, line.end == line.start + line.indentLength else { return nil }
        let code = block.filter { doc.lines[$0].kind == .code }
        guard code.count >= 2, code.last == index else { return nil }
        let indent = doc.string(in: doc.lines[block.lowerBound].indentRange)
        let last = doc.lines[block.upperBound]
        if last.kind == .fenceClose {
            let from = doc.lines[index - 1].end
            let replacement = "\n" + doc.string(in: last.range) + "\n" + indent
            return TextEdit(
                range: NSRange(location: from, length: last.end - from),
                replacement: replacement,
                selection: NSRange(location: from + replacement.utf16.count, length: 0)
            )
        }
        let replacement = indent + "```\n" + indent
        return TextEdit(
            range: NSRange(location: line.start, length: line.end - line.start),
            replacement: replacement,
            selection: NSRange(location: line.start + replacement.utf16.count, length: 0)
        )
    }

    static func removingLastIndentUnit(_ doc: MarkdownDocument, line: MarkdownLine, caret: Int? = nil) -> TextEdit {
        let indentEnd = line.start + line.indentLength
        var length = 1
        if doc.units[indentEnd - 1] == 0x20, line.indentLength >= 2, doc.units[indentEnd - 2] == 0x20 { length = 2 }
        return TextEdit(
            range: NSRange(location: indentEnd - length, length: length),
            replacement: "",
            selection: NSRange(location: (caret ?? indentEnd) - length, length: 0)
        )
    }
}
