import Foundation

nonisolated extension EditorCommands {
    /// Return. 목록은 같은 기호로 이어 가고, 빈 항목에서는 기호를 지우거나 한 단계 내어 쓴다.
    static func newline(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit {
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        let indent = doc.string(in: line.indentRange)
        let isCaret = selection.length == 0

        switch line.kind {
        case .code:
            // 코드의 들여쓰기(커서 앞까지)를 다음 줄로 가져간다.
            var end = line.start
            while end < min(line.end, selection.location), doc.units[end] == 0x09 || doc.units[end] == 0x20 { end += 1 }
            return .insert("\n" + doc.string(in: NSRange(location: line.start, length: end - line.start)), replacing: selection)

        case .fenceOpen:
            // ``` 를 치고 Return 하면 닫는 줄을 함께 넣는다.
            let block = line.codeBlock ?? index...index
            let isClosed = block.upperBound != index && doc.lines[block.upperBound].kind == .fenceClose
            if isCaret, selection.location == line.end, !isClosed {
                return TextEdit(
                    range: selection,
                    replacement: "\n" + indent + "\n" + indent + "```",
                    selection: NSRange(location: selection.location + 1 + line.indentLength, length: 0)
                )
            }
            return .insert("\n" + indent, replacing: selection)

        case .fenceClose:
            return .insert("\n", replacing: selection)

        case .heading:
            return .insert("\n" + (selection.location >= line.contentStart ? indent : ""), replacing: selection)

        case .paragraph:
            if isCaret, line.contentRange.length == 0, line.indentLength > 0 {
                return removingLastIndentUnit(doc, line: line)
            }
            return .insert("\n" + indent, replacing: selection)

        case .todo, .bullet, .toggle:
            if isCaret, line.contentRange.length == 0 {
                if line.indentLength > 0, let edit = outdent(doc, selection: selection, folded: folded) { return edit }
                return TextEdit(range: line.markerRange, replacement: "", selection: NSRange(location: line.start + line.indentLength, length: 0))
            }
            let marker = doc.string(in: line.markerRange)
            switch line.kind {
            case .todo:
                return .insert("\n" + indent + (marker.hasPrefix("[") ? "[ ] " : String(marker.prefix(2)) + "[ ] "), replacing: selection)
            case .toggle:
                if isCaret, folded.contains(index) {
                    // 접힌 토글은 감춘 줄들 뒤에 새 토글을 만든다.
                    let at = doc.lines[line.subtreeEnd - 1].end
                    let text = "\n" + indent + "> "
                    return TextEdit(
                        range: NSRange(location: at, length: 0),
                        replacement: text,
                        selection: NSRange(location: at + text.utf16.count, length: 0),
                        includesHiddenLines: true
                    )
                }
                // 펼친 토글은 안쪽 첫 줄을 만든다.
                return .insert("\n" + indent + "\t", replacing: selection)
            default:
                return .insert("\n" + indent + marker, replacing: selection)
            }
        }
    }

    /// ⌫. 줄 머리 바로 뒤에서 누르면 기호를 지우거나(목록) 한 단계 내어 쓴다(들여 쓴 문단).
    /// 그 밖에는 `nil`(기본 동작).
    static func deleteBackward(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let line = doc.lines[doc.lineIndex(at: selection.location)]
        guard selection.location == line.contentStart, line.prefixLength > 0 else { return nil }
        switch line.kind {
        case .todo, .bullet, .toggle:
            return TextEdit(range: line.markerRange, replacement: "", selection: NSRange(location: line.start + line.indentLength, length: 0))
        case .paragraph:
            return removingLastIndentUnit(doc, line: line)
        default:
            return nil
        }
    }

    /// ⌦. 줄 끝에서 누르면 줄바꿈과 함께 아랫줄의 감춘 줄 머리(들여쓰기와 목록 기호)를 지운다.
    /// 그대로 두면 감춰 있던 기호가 글자로 드러난다. 그 밖에는 `nil`(기본 동작).
    static func deleteForward(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        guard selection.location == line.end, index + 1 < doc.lines.count else { return nil }
        let next = doc.lines[index + 1]
        guard next.caretStart > next.start else { return nil }
        return TextEdit(
            range: NSRange(location: line.end, length: next.caretStart - line.end),
            replacement: "",
            selection: selection
        )
    }

    private static func removingLastIndentUnit(_ doc: MarkdownDocument, line: MarkdownLine) -> TextEdit {
        let indentEnd = line.start + line.indentLength
        var length = 1
        if doc.units[indentEnd - 1] == 0x20, line.indentLength >= 2, doc.units[indentEnd - 2] == 0x20 { length = 2 }
        return TextEdit(
            range: NSRange(location: indentEnd - length, length: length),
            replacement: "",
            selection: NSRange(location: indentEnd - length, length: 0)
        )
    }

    /// Space를 치기 직전. `[]` 뒤라면 투두 기호(`[ ] `)로 바꾼다.
    /// `#`, `-`, `>` 뒤의 Space는 그대로 넣으면 그 문법이 되므로 따로 바꾸지 않는다.
    static func spaceTrigger(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let line = doc.lines[doc.lineIndex(at: selection.location)]
        guard line.kind == .paragraph || line.kind == .bullet,
              selection.location == line.contentStart + 2,
              doc.string(in: NSRange(location: line.contentStart, length: 2)) == "[]"
        else { return nil }
        return TextEdit(
            range: NSRange(location: line.contentStart, length: 2),
            replacement: "[ ] ",
            selection: NSRange(location: line.contentStart + 4, length: 0)
        )
    }
}
