import Foundation

nonisolated extension EditorCommands {
    struct BlockPaste {
        let edit: TextEdit
        let roots: [Int]
    }

    /// 코드 본문의 공백과 강제 줄바꿈 뒤 글자는 보존하고 블록 들여쓰기만 옮긴다.
    static func rebasedLines(_ fragment: MarkdownDocument, depth: Int, atCaret: Bool = false) -> [String] {
        let base = fragment.lines.filter { $0.range.length > 0 && $0.continuationOf == nil }.map(\.level).min() ?? 0
        return fragment.lines.enumerated().map { index, line in
            let level = min(MarkdownDocument.maxLevel, depth + max(0, line.level - base))
            let prefix = String(repeating: "\t", count: atCaret && index == 0 ? max(0, level - depth) : level)
            let start = line.start + line.indentLength
            return prefix + fragment.string(in: NSRange(location: start, length: line.end - start))
        }
    }

    static func blockPaste(_ doc: MarkdownDocument, text: String, target: Int, belowRow: Int,
                           inside: Bool, folded: Set<Int>) -> BlockPaste? {
        guard !text.isEmpty else { return nil }
        let block = doc.lines[target].codeBlock ?? doc.blockLines(at: target)
        let line = doc.lines[block.lowerBound]
        let isDivider = line.kind == .divider || ["---", "***", "___"].contains(doc.string(in: line.contentRange).trimmingCharacters(in: .whitespaces))
        let child = inside && !line.kind.isCode && !isDivider && line.level < MarkdownDocument.maxLevel
        let after = child ? block.upperBound : max(belowRow, block.upperBound)
        let fragment = MarkdownDocument(text)
        var lines = rebasedLines(fragment, depth: line.level + (child ? 1 : 0))
        if lines.count > 1, fragment.lines.last?.range.length == 0 { lines.removeLast() }
        if hasUnterminatedFence(fragment), let open = fragment.lines.last(where: { $0.kind == .fenceOpen }) {
            let indent = lines[fragment.lineIndex(at: open.start)].prefix { $0 == "\t" }
            lines.append(indent + "```")
        }
        let source = lines.joined(separator: "\n")
        let inserted = MarkdownDocument(source)
        var roots: [Int] = []
        var row = 0
        while row < inserted.lines.count {
            roots.append(after + 1 + row)
            row = max(inserted.lines[row].subtreeEnd, (inserted.lines[row].codeBlock?.upperBound ?? row) + 1)
        }
        let at = doc.lines[after].end
        let folds = Set(folded.filter { !child || $0 != block.lowerBound }.map { $0 > after ? $0 + lines.count : $0 })
        let edit = TextEdit(range: NSRange(location: at, length: 0), replacement: "\n" + source,
                            selection: NSRange(location: at + 1 + inserted.lines[0].caretStart, length: 0),
                            foldedAfter: folds, includesHiddenLines: true)
        return BlockPaste(edit: edit, roots: roots)
    }

    static func pasteAtParentEnd(_ doc: MarkdownDocument, text: String, selection: NSRange, folded: Set<Int>) -> BlockPaste? {
        guard selection.length == 0, text.contains("\n") else { return nil }
        let row = doc.lineIndex(at: selection.location)
        let block = doc.blockLines(at: row)
        let owner = doc.lines[block.lowerBound]
        guard !owner.kind.isCode, owner.level < MarkdownDocument.maxLevel, row == block.upperBound, doc.lines[row].isVisualEnd(selection.location), !folded.contains(block.lowerBound),
              owner.kind.isToggle || owner.subtreeEnd > row + 1 else { return nil }
        let fragment = MarkdownDocument(text)
        let last = fragment.lines.count - (fragment.lines.last?.range.length == 0 ? 1 : 0)
        let first = fragment.lines[0].codeBlock ?? fragment.blockLines(at: 0)
        guard first.upperBound + 1 < last else { return nil }
        return blockPaste(doc, text: text, target: block.lowerBound, belowRow: row, inside: true, folded: folded)
    }
}
