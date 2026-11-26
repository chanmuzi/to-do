import Foundation

nonisolated extension EditorCommands {
    static func setBlockInk(_ doc: MarkdownDocument, owners: [Int], color: InkColor?, toggle: Bool) -> TextEdit? {
        let ends = Set(owners.filter { !doc.lines[$0].kind.isCode }.map { doc.blockLines(at: $0).upperBound }).sorted()
        guard let first = ends.first, let last = ends.last else { return nil }
        let remove = toggle && ends.allSatisfy { doc.lines[$0].blockInk == color }
        let comment = remove ? "" : color?.comment ?? ""
        let range = doc.sourceRange(for: first...last)
        let replacement = NSMutableString(string: doc.string(in: range))
        for row in ends.reversed() {
            let line = doc.lines[row]
            let marker = line.inkComment ?? NSRange(location: line.end, length: 0)
            replacement.replaceCharacters(in: NSRange(location: marker.location - range.location, length: marker.length), with: comment)
        }
        guard doc.string(in: range) != replacement as String else { return nil }
        return TextEdit(range: range, replacement: replacement as String,
                        selection: NSRange(location: doc.lines[first].caretStart, length: 0),
                        preservesLines: true, includesHiddenLines: true)
    }

    /// Return으로 갈라지는 블록의 끝 주석을 새 개행 앞으로 옮긴다.
    static func keepingInkOnSplit(_ doc: MarkdownDocument, selection: NSRange, edit: TextEdit) -> TextEdit {
        let block = doc.blockLines(at: doc.lineIndex(at: selection.location))
        guard let comment = doc.lines[block.upperBound].inkComment,
              NSMaxRange(edit.range) <= comment.location,
              let newline = edit.replacement.firstIndex(of: "\n") else { return edit }
        var result = edit
        let tail = NSRange(location: NSMaxRange(edit.range), length: comment.location - NSMaxRange(edit.range))
        result.replacement.insert(contentsOf: doc.string(in: comment), at: newline)
        result.replacement += doc.string(in: tail)
        result.range.length = NSMaxRange(comment) - edit.range.location
        result.selection.location += comment.length
        return result
    }

    /// 두 블록을 합칠 때 앞 블록의 주석만 합쳐진 블록 끝에 둔다.
    static func joiningColoredBlocks(_ doc: MarkdownDocument, before row: Int) -> TextEdit? {
        let left = doc.lines[row - 1]
        let right = doc.lines[row]
        let last = doc.lines[doc.blockLines(at: row).upperBound]
        guard left.inkComment != nil || last.inkComment != nil else { return nil }
        let start = left.inkComment?.location ?? left.end
        let end = last.inkComment?.location ?? last.end
        let body = doc.string(in: NSRange(location: right.contentStart, length: end - right.contentStart))
        return TextEdit(range: NSRange(location: start, length: last.end - start),
                        replacement: body + (left.blockInk?.comment ?? ""),
                        selection: NSRange(location: start, length: 0))
    }
}
