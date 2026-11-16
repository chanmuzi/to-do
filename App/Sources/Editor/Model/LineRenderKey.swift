import Foundation

/// 한 줄을 어떻게 그릴지 정하는 값. 글자가 그대로여도 이 값이 달라진 줄은 다시 입힌다.
nonisolated struct LineRenderKey: Hashable, Sendable {
    var kind: LineKind
    var level: Int
    /// 커서(선택)가 있는 줄. 마크다운 기호를 보인다.
    var isActive = false
    /// 접힌 토글 안의 줄. 높이 없이 감춘다.
    var isCollapsed = false
    /// 접힌 토글 자신.
    var isFolded = false
    var childCount = 0
    /// 문서의 첫 줄(위 여백을 두지 않는다).
    var isFirst = false
    /// 코드 블록에 커서가 있어 ``` 줄을 보인다.
    var isCodeActive = false
    /// 코드 블록의 첫 줄, 마지막 줄(상자의 둥근 모서리를 그린다).
    var isCodeTop = false
    var isCodeBottom = false
    /// 마우스가 올라간 링크의 줄 안 위치.
    var hoveredLink: Int?
}

nonisolated enum LinePresentation {
    /// - Parameter active: 선택이 걸친 줄. 편집기에 포커스가 없으면 `nil`.
    static func keys(
        for doc: MarkdownDocument,
        active: ClosedRange<Int>?,
        folded: Set<Int>,
        hoveredLink: (line: Int, offset: Int)? = nil
    ) -> [LineRenderKey] {
        let folded = FoldState.sanitized(folded, in: doc)
        let hidden = FoldState.hiddenLines(doc, folded: folded)
        return doc.lines.indices.map { index in
            let line = doc.lines[index]
            var key = LineRenderKey(kind: line.kind, level: line.level)
            key.isCollapsed = hidden.contains(index)
            key.isActive = !key.isCollapsed && (active?.contains(index) ?? false)
            key.isFolded = folded.contains(index)
            key.childCount = line.kind == .toggle ? line.childCount : 0
            key.isFirst = index == 0
            if let block = line.codeBlock {
                key.isCodeActive = active.map { $0.overlaps(block) } ?? false
                key.isCodeTop = index == block.lowerBound
                key.isCodeBottom = index == block.upperBound
            }
            if let hoveredLink, hoveredLink.line == index { key.hoveredLink = hoveredLink.offset }
            return key
        }
    }

    /// 달라진 줄의 범위(새 문서의 줄 번호). 앞뒤로 같은 부분을 빼고 남은 가운데다.
    static func changedLines(old: [LineRenderKey], new: [LineRenderKey]) -> Range<Int>? {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let range = prefix..<(new.count - suffix)
        return range.isEmpty ? nil : range
    }
}
