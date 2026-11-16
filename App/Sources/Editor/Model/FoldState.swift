import Foundation

/// 접힌 토글. 접힘은 원문에 적지 않고 줄 번호로 따로 들고 있다.
nonisolated enum FoldState {
    /// 토글이 아닌 줄 번호를 버린다.
    static func sanitized(_ folded: Set<Int>, in doc: MarkdownDocument) -> Set<Int> {
        folded.filter { $0 >= 0 && $0 < doc.lines.count && doc.lines[$0].kind == .toggle }
    }

    /// 접혀서 보이지 않는 줄 번호.
    static func hiddenLines(_ doc: MarkdownDocument, folded: Set<Int>) -> Set<Int> {
        var hidden = Set<Int>()
        for index in sanitized(folded, in: doc) {
            hidden.formUnion((index + 1)..<doc.lines[index].subtreeEnd)
        }
        return hidden
    }

    /// 그 줄을 감추고 있는 가장 바깥의 접힌 토글.
    static func foldRoot(of line: Int, in doc: MarkdownDocument, folded: Set<Int>) -> Int? {
        sanitized(folded, in: doc).filter { $0 < line && doc.lines[$0].subtreeEnd > line }.min()
    }

    /// 원문이 바뀐 뒤의 접힌 줄 번호. 바뀐 곳 앞은 그대로, 뒤는 늘거나 준 줄 수만큼 옮긴다.
    /// - Parameters:
    ///   - editedRange: 바뀐 범위(바뀐 뒤의 원문 기준).
    ///   - delta: 길이 변화.
    static func remapped(
        _ folded: Set<Int>,
        old: MarkdownDocument,
        new: MarkdownDocument,
        editedRange: NSRange,
        delta: Int
    ) -> Set<Int> {
        guard !folded.isEmpty else { return folded }
        let oldEnd = min(old.length, editedRange.location + editedRange.length - delta)
        let firstLine = old.lineIndex(at: min(editedRange.location, old.length))
        let lastLine = old.lineIndex(at: max(oldEnd, 0))
        let lineDelta = new.lines.count - old.lines.count
        var result = Set<Int>()
        for index in folded {
            if index < firstLine {
                result.insert(index)
            } else if index > lastLine {
                result.insert(index + lineDelta)
            } else if index == firstLine {
                // 토글 제목 줄 안에서 고친 경우. 줄 맨 앞에 끼워 넣은 것이면 토글이 아래로 밀린다.
                let insertedAtLineStart = oldEnd == editedRange.location && editedRange.location == old.lines[index].start
                result.insert(insertedAtLineStart ? index + lineDelta : index)
            }
        }
        return sanitized(result, in: new)
    }

    /// 접기. 커서 줄이 토글이면 그 줄을, 아니면 그 줄을 품은 가장 가까운 토글을 접는다.
    static func fold(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> (folded: Set<Int>, selection: NSRange)? {
        let index = doc.lineIndex(at: selection.location)
        var target: Int?
        if doc.lines[index].kind == .toggle, !folded.contains(index) {
            target = index
        } else {
            target = (0..<index).reversed().first {
                doc.lines[$0].kind == .toggle && doc.lines[$0].subtreeEnd > index && !folded.contains($0)
            }
        }
        guard let target else { return nil }
        let title = doc.lines[target]
        let inside = selection.location > title.end || NSMaxRange(selection) > title.end
        return (folded.union([target]), inside ? NSRange(location: title.end, length: 0) : selection)
    }

    /// 펼치기. 커서 줄이 접힌 토글일 때만.
    static func unfold(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> Set<Int>? {
        let index = doc.lineIndex(at: selection.location)
        guard folded.contains(index) else { return nil }
        return folded.subtracting([index])
    }
}
