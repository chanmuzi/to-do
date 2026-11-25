import Foundation

nonisolated extension EditorCommands {
    /// Return. 목록은 같은 기호로 이어 가고, 빈 항목에서는 기호를 지우거나 한 단계 내어 쓴다.
    /// 서식 구간 한가운데에서 누르면 구간을 줄바꿈 앞에서 닫고 다음 줄에서 다시 연다.
    static func newline(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit {
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        let indent = doc.string(in: line.indentRange)
        let isCaret = selection.length == 0
        // 커서 뒤의 공백은 줄바꿈과 함께 지운다. 남겨 두면 새 줄의 맨 앞에서 감춘 들여쓰기가 된다.
        var selection = selection
        if !line.kind.isCode, selection.location >= line.contentStart {
            let endLine = doc.line(at: NSMaxRange(selection))
            var upper = NSMaxRange(selection)
            while upper < endLine.end, doc.units[upper] == 0x20 || doc.units[upper] == 0x09 { upper += 1 }
            selection.length = upper - selection.location
        }

        switch line.kind {
        case .code:
            if isCaret, let exit = leavingCodeBlock(doc, lineIndex: index) { return exit }
            // 코드의 들여쓰기(커서 앞까지)를 다음 줄로 가져간다.
            var end = line.start
            while end < min(line.end, selection.location), doc.units[end] == 0x09 || doc.units[end] == 0x20 { end += 1 }
            return .insert("\n" + doc.string(in: NSRange(location: line.start, length: end - line.start)), replacing: selection)

        case .fenceOpen, .fenceClose:
            // 줄이 없는 블록의 커서 자리: 빈 코드 줄 둘을 만들고 둘째 줄로 간다.
            if isCaret, let block = emptyBlock(doc, caretAt: selection.location) {
                return insertingIntoEmptyBlock(doc, block, "\n")
            }
            // ``` 줄에는 커서가 놓이지 않는다. 놓였더라도 줄만 나눈다.
            return .insert("\n" + (line.kind == .fenceOpen ? indent : ""), replacing: selection)

        case .heading:
            return insert(doc, "\n" + (selection.location >= line.contentStart ? indent : ""), replacing: selection)

        case .paragraph:
            if isCaret, line.contentRange.length == 0, line.indentLength > 0 {
                return removingLastIndentUnit(doc, line: line)
            }
            return insert(doc, "\n" + indent, replacing: selection)

        case .todo, .bullet, .toggle, .toggleHeading, .quote:
            // 빈 항목(빈 인용문 줄 포함)에서는 기호를 지우거나 한 단계 내어 쓴다. 인용문은 `> `로 이어 간다.
            if isCaret, line.contentRange.length == 0 {
                if line.indentLength > 0, let edit = outdent(doc, selection: selection, folded: folded) { return edit }
                return TextEdit(range: line.markerRange, replacement: "", selection: NSRange(location: line.start + line.indentLength, length: 0))
            }
            let marker = doc.string(in: line.markerRange)
            switch line.kind {
            case .todo:
                let next = marker.hasPrefix("[") ? "[ ] " : String(marker.prefix(2)) + "[ ] "
                return insert(doc, "\n" + indent + next, replacing: selection)
            case .toggle, .toggleHeading:
                if isCaret, folded.contains(index) {
                    // 접힌 토글은 감춘 줄들 뒤에 새 토글을 만든다.
                    let at = doc.lines[line.subtreeEnd - 1].end
                    let text = "\n" + indent + "+ "
                    return TextEdit(
                        range: NSRange(location: at, length: 0),
                        replacement: text,
                        selection: NSRange(location: at + text.utf16.count, length: 0),
                        includesHiddenLines: true
                    )
                }
                // 펼친 토글은 안쪽 첫 줄을 만든다.
                return insert(doc, "\n" + indent + "\t", replacing: selection)
            default:
                return insert(doc, "\n" + indent + marker, replacing: selection)
            }
        }
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
