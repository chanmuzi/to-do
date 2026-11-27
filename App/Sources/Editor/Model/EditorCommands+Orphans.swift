import Foundation

// 부모 항목을 지우거나 내어 쓰거나 본문으로 바꾸면, 그 아래에서 부모를 잃는 하위 줄을 함께 내어 쓴다(D-043).
// 편집 하나에 붙여 한 번의 편집(되돌리기 한 단계)으로 넣는다. 편집 전에도 부모가 없던 줄(다른 프로그램이 쓴
// 파일의 깊은 들여쓰기)은 건드리지 않는다.
//
// 내어 쓰기는 편집이 "하위 줄을 가진 부모 줄"의 종류나 단계를 바꿨을 때(기호를 지움, ⇧Tab, 빈 항목의 Return,
// 그 줄을 지우거나 덮어씀)만 따진다. 부모와 하위 줄 사이의 빈 줄을 채우는 입력은 하위 줄을 움직이지 않는다
// (영문 입력과 한글 조합이 같게 남는다). 그래서 거의 모든 키 입력은 편집한 줄만 보고 바로 돌아간다.

nonisolated extension EditorCommands {
    /// `edit`가 부모를 없앤 하위 줄을, 부모가 있는 단계까지 내어 쓰는 편집을 덧붙인다. 없으면 `edit` 그대로.
    /// 돌려주는 편집에는 `checkedForOrphans`가 붙어, 같은 편집을 다시 넘기면 따지지 않고 그대로 돌려준다.
    ///
    /// - 따지는 것은 편집한 줄 가운데 편집 전에 하위 줄을 가진 부모 줄이 있고, 편집이 그 줄들의 종류나 단계를
    ///   바꿨을 때뿐이다. 대상은 편집한 줄 바로 뒤의 하위 덩어리(그 부모보다 깊은 줄이 이어지는 동안)다.
    /// - 코드 블록의 줄은 블록째로 움직여야 해서 다루지 않는다(부모를 잃은 채 남는다).
    /// - 접혀서 감춘 줄은 제 토글과 함께 내어 쓸 때만 고친다. 아니면 편집기가 막고 토글을 편다(D-020).
    static func adoptingOrphans(_ doc: MarkdownDocument, _ edit: TextEdit, folded: Set<Int> = [], openedEmpty: Set<Int> = []) -> TextEdit {
        guard !edit.checkedForOrphans else { return edit }
        var checked = edit
        checked.checkedForOrphans = true
        let removals = orphanRemovals(doc, edit)
        guard let lastRemoved = removals.keys.max() else { return checked }

        // 편집한 범위의 앞에서부터 마지막으로 고친 줄의 끝까지를 한 번에 바꿔 쓴다. 고친 줄은 편집 범위 뒤에
        // 있으므로(원문 그대로인 글) 원문에서 이어 붙인다.
        let delta = edit.replacement.utf16.count - edit.range.length
        let regionStart = edit.range.location
        let regionEnd = doc.lines[lastRemoved].end
        var replacement = edit.replacement
        var cursor = NSMaxRange(edit.range)
        // 바꾼 뒤 원문 기준으로 지운 들여쓰기의 자리와 길이.
        var removedAfter: [(position: Int, length: Int)] = []
        for (index, length) in removals.sorted(by: { $0.key < $1.key }) {
            let start = doc.lines[index].start
            replacement += doc.string(in: NSRange(location: cursor, length: start - cursor))
            cursor = start + length
            removedAfter.append((start + delta, length))
        }
        replacement += doc.string(in: NSRange(location: cursor, length: regionEnd - cursor))

        func moved(_ position: Int) -> Int {
            position - removedAfter.reduce(0) { total, removal in
                position >= removal.position + removal.length ? total + removal.length
                    : position > removal.position ? total + (position - removal.position) : total
            }
        }
        var result = checked
        result.range = NSRange(location: regionStart, length: regionEnd - regionStart)
        result.replacement = replacement
        let start = moved(edit.selection.location)
        result.selection = NSRange(location: start, length: max(0, moved(NSMaxRange(edit.selection)) - start))
        if !edit.preservesLines {
            // 내어 쓰기는 줄 수를 바꾸지 않으므로 원래 편집을 기준으로 두 기록을 옮긴다.
            let after = MarkdownDocument(edit.applied(to: doc.text))
            let range = NSRange(location: edit.range.location, length: edit.replacement.utf16.count)
            if edit.foldedAfter == nil, !folded.isEmpty {
                result.foldedAfter = FoldState.remapped(folded, old: doc, new: after, editedRange: range, delta: delta)
            }
            if edit.openTogglesAfter == nil {
                let state = FoldState(closed: folded, openedEmpty: openedEmpty)
                result.openTogglesAfter = FoldState.remapped(state.openToggleLines(in: doc), old: doc, new: after, editedRange: range, delta: delta)
            }
        }
        if !edit.includesHiddenLines, !folded.isEmpty {
            result.includesHiddenLines = movesFoldedBlocksWhole(doc, edit, moved: Set(removals.keys), folded: folded)
        }
        return result
    }

    /// 내어 쓸 줄(편집 전 원문의 줄 번호)과 지울 들여쓰기 길이. 편집한 줄과 그 뒤의 하위 덩어리만 본다.
    private static func orphanRemovals(_ doc: MarkdownDocument, _ edit: TextEdit) -> [Int: Int] {
        let first = doc.lineIndex(at: edit.range.location)
        let last = doc.lineIndex(at: NSMaxRange(edit.range))
        let oldRegion = first...last
        let regionStart = doc.lines[first].start
        let editEnd = NSMaxRange(edit.range)
        let delta = edit.replacement.utf16.count - edit.range.length
        // 편집한 줄들만 바꿔 다시 읽는다(편집 뒤 원문의 `regionStart`부터).
        let newRegion = MarkdownDocument(
            (doc.string(in: NSRange(location: regionStart, length: doc.lines[last].end - regionStart)) as NSString)
                .replacingCharacters(in: NSRange(location: edit.range.location - regionStart, length: edit.range.length), with: edit.replacement)
        )
        let newStarts = Set(newRegion.lines.map(\.start))
        // 편집 범위 뒤에서 시작해 글자 그대로 남은 줄(선택이 그 줄 맨 앞에서 끝나는 지우기의 다음 줄).
        func isIntact(_ index: Int) -> Bool {
            let start = doc.lines[index].start
            return start >= editEnd && newStarts.contains(start + delta - regionStart)
        }
        // 편집이 고친, 하위 줄을 가진 부모 줄. 없으면(빈 줄이나 본문 줄을 채움) 아무 줄도 움직이지 않는다.
        let changedParents = oldRegion.filter { !isIntact($0) && ListStructure.hasChildren(doc, $0) }
        guard let minLevel = changedParents.map({ doc.lines[$0].level }).min() else { return [:] }
        // 종류와 단계가 그대로면 부모 관계도 그대로다.
        if newRegion.lines.count == oldRegion.count,
           zip(doc.lines[oldRegion], newRegion.lines).allSatisfy({ $0.kind == $1.kind && $0.level == $1.level }) {
            return [:]
        }

        // 부모 줄 뒤의 하위 덩어리: 가장 얕은 부모보다 깊은 줄(빈 줄 포함)이 이어지는 동안.
        var blockEnd = last + 1
        while blockEnd < doc.lines.count,
              ListStructure.isBlank(doc.lines[blockEnd]) || doc.lines[blockEnd].level > minLevel {
            blockEnd += 1
        }
        let block = (last + 1)..<blockEnd

        // 코드 블록이 걸리면 따로 읽은 줄의 종류가 문서 안에서와 다를 수 있다. 그때만 문서 전체를 다시 읽는다.
        let lineDelta = newRegion.lines.count - oldRegion.count
        let newRegionLines: [MarkdownLine]
        let newBlockLines: [MarkdownLine]
        if doc.lines[oldRegion].contains(where: \.kind.isCode) || newRegion.lines.contains(where: \.kind.isCode)
            || block.contains(where: { doc.lines[$0].kind.isCode }) {
            let new = MarkdownDocument(edit.applied(to: doc.text))
            newRegionLines = Array(new.lines[first..<(first + newRegion.lines.count)])
            newBlockLines = block.map { new.lines[$0 + lineDelta] }
        } else {
            newRegionLines = newRegion.lines
            newBlockLines = block.map { doc.lines[$0] }
        }

        // 편집 전에 부모가 있던 줄. 편집한 줄 앞의 문맥은 편집 전과 뒤가 같다.
        let before = ListStructure.context(before: first, in: doc)
        var oldContext = before
        var hadParent: [Int: Bool] = [:]
        for index in oldRegion.lowerBound..<blockEnd {
            let line = doc.lines[index]
            hadParent[index] = line.level == 0 || oldContext.hasParent(atLevel: line.level - 1)
            oldContext.add(line)
        }

        var newContext = before
        var removals: [Int: Int] = [:]
        // 편집 범위 뒤의 줄(그대로 남은 줄과 하위 덩어리)이 부모를 잃으면 부모가 있는 단계까지 내어 쓴다.
        // 그 글은 편집 뒤에도 그대로이므로 들여쓰기는 원문에서 잰다.
        func visit(_ newLine: MarkdownLine, old index: Int?) {
            var level = newLine.level
            if let index, hadParent[index] == true, level > 0, !newLine.kind.isCode {
                let oldLine = doc.lines[index]
                var length = 0
                var position = oldLine.start
                while level > 0, !newContext.hasParent(atLevel: level - 1) {
                    let unit = leadingIndentUnit(doc, at: position, limit: oldLine.start + oldLine.indentLength, spaces: 2)
                    guard unit > 0 else { break }
                    length += unit
                    position += unit
                    level -= 1
                }
                if length > 0 { removals[index] = length }
            }
            newContext.add(newLine, level: level)
        }
        let intact = Dictionary(uniqueKeysWithValues: oldRegion.filter(isIntact).map { (doc.lines[$0].start + delta - regionStart, $0) })
        for (newLine, local) in zip(newRegionLines, newRegion.lines) {
            visit(newLine, old: intact[local.start])
        }
        for (index, newLine) in zip(block, newBlockLines) {
            visit(newLine, old: index)
        }
        return removals
    }

    /// 덧붙인 내어 쓰기가 닿는 감춘 줄이 모두 제 토글과 함께 움직이는지. 원래 편집이 감춘 줄에 닿으면 아니다.
    /// - Parameter moved: 내어 쓰는 줄(편집 전 원문의 줄 번호).
    private static func movesFoldedBlocksWhole(_ doc: MarkdownDocument, _ edit: TextEdit, moved: Set<Int>, folded: Set<Int>) -> Bool {
        guard FoldState.brokenRoots(by: edit.range, in: doc, folded: folded).isEmpty else { return false }
        let hidden = FoldState.hiddenLines(doc, folded: folded)
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
