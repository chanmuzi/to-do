import Foundation

/// 여러 줄의 머리(들여쓰기와 기호)를 한 번에 바꾸는 편집을 만든다.
/// 들여쓰기, 제목, 투두 바꾸기가 모두 이것을 쓴다.
nonisolated enum LinePrefixEdit {
    /// 줄 맨 앞 `oldLength` 글자를 `new`로 바꾼다.
    struct Change {
        var oldLength: Int
        var new: String
    }

    /// - Parameter change: 줄마다 바꿀 내용. `nil`이면 그 줄은 그대로 둔다.
    /// - Returns: 바뀌는 줄이 하나도 없으면 `nil`.
    static func make(
        _ doc: MarkdownDocument,
        lines: ClosedRange<Int>,
        selection: NSRange,
        change: (MarkdownLine) -> Change?
    ) -> TextEdit? {
        let first = doc.lines[lines.lowerBound]
        let last = doc.lines[lines.upperBound]
        var replacement = ""
        var changed = false
        // 줄마다 (옛 시작, 새 시작, 옛 머리 길이, 새 머리 길이)
        var map: [(oldStart: Int, newStart: Int, oldLength: Int, newLength: Int)] = []
        var newStart = first.start
        for index in lines {
            let line = doc.lines[index]
            let applied = change(line)
            let oldLength = applied?.oldLength ?? 0
            let new = applied?.new ?? ""
            if applied != nil, !(oldLength == new.utf16.count && doc.string(in: NSRange(location: line.start, length: oldLength)) == new) {
                changed = true
            }
            let rest = doc.string(in: NSRange(location: line.start + oldLength, length: line.end - line.start - oldLength))
            let terminator = index == lines.upperBound ? "" : doc.terminator(of: line)
            map.append((line.start, newStart, oldLength, new.utf16.count))
            let piece = new + rest + terminator
            replacement += piece
            newStart += piece.utf16.count
        }
        guard changed else { return nil }
        let range = NSRange(location: first.start, length: last.end - first.start)
        let delta = replacement.utf16.count - range.length

        func moved(_ position: Int) -> Int {
            if position < first.start { return position }
            if position > last.end { return position + delta }
            let entry = map.last { $0.oldStart <= position } ?? map[0]
            let offset = position - entry.oldStart
            let newOffset = offset < entry.oldLength
                ? min(offset, entry.newLength)
                : offset - entry.oldLength + entry.newLength
            return entry.newStart + newOffset
        }

        let start = moved(selection.location)
        let end = moved(NSMaxRange(selection))
        return TextEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: start, length: max(0, end - start)),
            preservesLines: true
        )
    }
}
