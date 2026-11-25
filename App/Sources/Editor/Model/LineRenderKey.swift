import Foundation

/// 한 줄을 어떻게 그릴지 정하는 값. 글자가 그대로여도 이 값이 달라진 줄은 다시 입힌다.
nonisolated struct LineRenderKey: Hashable, Sendable {
    var kind: LineKind
    var level: Int
    /// 접힌 토글 안의 줄. 높이 없이 감춘다.
    var isCollapsed = false
    /// 접힌 토글 자신.
    var isFolded = false
    /// 문서의 첫 줄(위 여백을 두지 않는다).
    var isFirst = false
    /// 코드 블록의 첫 줄, 마지막 줄(상자의 둥근 모서리를 그린다).
    var isCodeTop = false
    var isCodeBottom = false
    /// 닫히지 않은 코드 블록이 줄바꿈으로 끝나서, 이 줄 바로 뒤에 문서 끝의 빈 코드 줄이 있다.
    /// 그 빈 줄은 문단이 따로 없고 이 줄의 조각에 붙어 그려지므로, 코드 상자를 그 줄까지 늘려 닫는다.
    var hasTrailingCodeLine = false
    /// 코드 줄이 없는 블록의 ``` 줄 가운데 커서가 놓이는 줄(`EditorCommands.emptyBlockCaret`).
    /// 빈 코드 줄 하나의 높이로 그려, 블록에 들어가 쓸 수 있게 한다.
    var isEmptyBlockSpot = false
    /// 마우스가 올라간 링크의 줄 안 위치.
    var hoveredLink: Int?
}

nonisolated enum LinePresentation {
    static func keys(
        for doc: MarkdownDocument,
        folded: Set<Int>,
        hoveredLink: (line: Int, offset: Int)? = nil
    ) -> [LineRenderKey] {
        let folded = FoldState.sanitized(folded, in: doc)
        let hidden = FoldState.hiddenLines(doc, folded: folded)
        let trailingCode = trailingCodeLine(in: doc) != nil
        return doc.lines.indices.map { index in
            let line = doc.lines[index]
            var key = LineRenderKey(kind: line.kind, level: line.level)
            key.isCollapsed = hidden.contains(index)
            key.isFolded = folded.contains(index)
            key.isFirst = index == 0
            if let block = line.codeBlock {
                key.isCodeTop = index == block.lowerBound
                key.isCodeBottom = index == block.upperBound
                key.isEmptyBlockSpot = index == block.upperBound && line.kind != .code
                    && EditorCommands.emptyBlock(doc, at: index) != nil
            }
            if let hoveredLink, hoveredLink.line == index { key.hoveredLink = hoveredLink.offset }
            key.hasTrailingCodeLine = trailingCode && index == doc.lines.count - 2 && !key.isCollapsed
            return key
        }
    }

    /// 문서 끝의 빈 줄이 닫히지 않은 코드 블록 안이면 그 줄.
    static func trailingCodeLine(in doc: MarkdownDocument) -> MarkdownLine? {
        guard doc.lines.count >= 2, let last = doc.lines.last, last.range.length == 0, last.kind == .code else { return nil }
        return last
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
