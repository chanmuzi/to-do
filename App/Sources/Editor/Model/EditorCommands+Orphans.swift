import Foundation

// 부모 항목을 지우거나 내어 쓰거나 본문으로 바꾸면, 그 아래에서 부모를 잃는 하위 줄을 함께 내어 쓴다(D-043).
// 편집 하나에 붙여 한 번의 편집(되돌리기 한 단계)으로 넣는다. 편집 전에도 부모가 없던 줄(다른 프로그램이 쓴
// 파일의 깊은 들여쓰기)은 건드리지 않는다.

nonisolated extension EditorCommands {
    /// `edit`가 부모를 없앤 하위 줄을, 부모가 있는 단계까지 내어 쓰는 편집을 덧붙인다. 없으면 `edit` 그대로.
    ///
    /// - 대상은 편집한 범위 뒤의 줄이다. 편집한 줄 자신은 편집이 정한 대로 둔다.
    /// - 코드 블록의 줄은 블록째로 움직여야 해서 다루지 않는다(부모를 잃은 채 남는다).
    /// - 접혀서 감춘 줄은 제 토글과 함께 내어 쓸 때만 고친다. 아니면 편집기가 막고 토글을 편다(D-020).
    static func adoptingOrphans(_ doc: MarkdownDocument, _ edit: TextEdit, folded: Set<Int> = []) -> TextEdit {
        guard doc.lines.contains(where: { $0.level > 0 }) else { return edit }
        let delta = edit.replacement.utf16.count - edit.range.length
        let editEnd = edit.range.location + edit.replacement.utf16.count
        let new = MarkdownDocument(edit.applied(to: doc.text))
        let hadParent = ListStructure.hasParent(in: doc)

        var context = ListStructure.Context()
        // 새 문서의 줄 번호 → 지울 들여쓰기 길이.
        var removals: [Int: Int] = [:]
        for (index, line) in new.lines.enumerated() {
            var level = line.level
            if line.start >= editEnd, level > 0, !line.kind.isCode {
                let oldStart = line.start - delta
                let oldIndex = doc.lineIndex(at: oldStart)
                if doc.lines[oldIndex].start == oldStart, hadParent[oldIndex] {
                    var length = 0
                    var position = line.start
                    while level > 0, !context.hasParent(atLevel: level - 1) {
                        let unit = leadingIndentUnit(new, at: position, limit: line.start + line.indentLength, spaces: 2)
                        guard unit > 0 else { break }
                        length += unit
                        position += unit
                        level -= 1
                    }
                    if length > 0 { removals[index] = length }
                }
            }
            context.add(line, level: level)
        }
        guard let lastIndex = removals.keys.max() else { return edit }

        // 편집한 범위의 앞에서부터 마지막으로 고친 줄의 끝까지를 한 번에 바꿔 쓴다.
        let regionStart = edit.range.location
        let regionEnd = new.lines[lastIndex].end
        var replacement = ""
        var cursor = regionStart
        var removedBefore: [(position: Int, length: Int)] = []
        for (index, length) in removals.sorted(by: { $0.key < $1.key }) {
            let start = new.lines[index].start
            replacement += new.string(in: NSRange(location: cursor, length: start - cursor))
            cursor = start + length
            removedBefore.append((start, length))
        }
        replacement += new.string(in: NSRange(location: cursor, length: regionEnd - cursor))

        func moved(_ position: Int) -> Int {
            position - removedBefore.reduce(0) { total, removal in
                position >= removal.position + removal.length ? total + removal.length
                    : position > removal.position ? total + (position - removal.position) : total
            }
        }
        var result = edit
        result.range = NSRange(location: regionStart, length: regionEnd - delta - regionStart)
        result.replacement = replacement
        let start = moved(edit.selection.location)
        result.selection = NSRange(location: start, length: max(0, moved(NSMaxRange(edit.selection)) - start))
        if !edit.preservesLines, edit.foldedAfter == nil, !folded.isEmpty {
            // 바꿔 쓰는 범위가 넓어져도 접힘은 원래 편집을 따라 옮긴다(내어 쓰기는 줄 수를 바꾸지 않는다).
            result.foldedAfter = FoldState.remapped(
                folded, old: doc, new: new,
                editedRange: NSRange(location: edit.range.location, length: edit.replacement.utf16.count), delta: delta
            )
        }
        if !edit.includesHiddenLines, !folded.isEmpty {
            result.includesHiddenLines = movesFoldedBlocksWhole(doc, edit, removals: removals, new: new, delta: delta, folded: folded)
        }
        return result
    }

    /// 덧붙인 내어 쓰기가 닿는 감춘 줄이 모두 제 토글과 함께 움직이는지. 원래 편집이 감춘 줄에 닿으면 아니다.
    private static func movesFoldedBlocksWhole(
        _ doc: MarkdownDocument, _ edit: TextEdit, removals: [Int: Int], new: MarkdownDocument, delta: Int, folded: Set<Int>
    ) -> Bool {
        guard FoldState.brokenRoots(by: edit.range, in: doc, folded: folded).isEmpty else { return false }
        let hidden = FoldState.hiddenLines(doc, folded: folded)
        let moved = Set(removals.keys.map { doc.lineIndex(at: new.lines[$0].start - delta) })
        let edited = doc.lineRange(for: edit.range)
        guard let last = moved.max(), edited.upperBound <= last else { return false }
        // 토글 자신을 고친 편집(기호를 지워 본문으로 바꿈)이면 그 토글의 감춘 줄도 함께 내어 써도 된다.
        return (edited.upperBound...last).allSatisfy { index in
            guard hidden.contains(index) else { return true }
            guard let root = FoldState.foldRoot(of: index, in: doc, folded: folded) else { return true }
            let title = doc.lines[root]
            let touched = title.start <= NSMaxRange(edit.range) && title.end >= edit.range.location
            return moved.contains(index) && (moved.contains(root) || touched)
        }
    }
}
