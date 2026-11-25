import Foundation

/// 접힌 토글. 접힘은 원문에 적지 않고 줄 번호로 따로 들고 있다.
nonisolated enum FoldState {
    /// 토글이 아닌 줄 번호를 버린다.
    static func sanitized(_ folded: Set<Int>, in doc: MarkdownDocument) -> Set<Int> {
        folded.filter { $0 >= 0 && $0 < doc.lines.count && doc.lines[$0].kind.isToggle }
    }

    /// 접혀서 보이지 않는 줄 번호.
    static func hiddenLines(_ doc: MarkdownDocument, folded: Set<Int>) -> Set<Int> {
        var hidden = Set<Int>()
        for index in sanitized(folded, in: doc) {
            hidden.formUnion((doc.blockLines(at: index).upperBound + 1)..<doc.lines[index].subtreeEnd)
        }
        return hidden
    }

    /// 그 줄들 가운데 접혀서 보이지 않는 줄이 있는지.
    static func hidesAny(of lines: ClosedRange<Int>, in doc: MarkdownDocument, folded: Set<Int>) -> Bool {
        !hiddenLines(doc, folded: folded).isDisjoint(with: lines)
    }

    /// 그 줄을 감추고 있는 가장 바깥의 접힌 토글.
    static func foldRoot(of line: Int, in doc: MarkdownDocument, folded: Set<Int>) -> Int? {
        sanitized(folded, in: doc).filter { doc.blockLines(at: $0).upperBound < line && doc.lines[$0].subtreeEnd > line }.min()
    }

    /// 선택한 줄을 접힌 덩어리 단위로 넓힌다. 접힌 토글이 걸쳐 있으면 감춘 줄까지 넣는다.
    static func expanded(_ lines: ClosedRange<Int>, in doc: MarkdownDocument, folded: Set<Int>) -> ClosedRange<Int> {
        let folded = sanitized(folded, in: doc)
        var first = doc.blockLines(at: lines.lowerBound).lowerBound
        var last = doc.blockLines(at: lines.upperBound).upperBound
        if let root = foldRoot(of: first, in: doc, folded: folded) { first = root }
        for index in first...last where folded.contains(index) {
            last = max(last, doc.lines[index].subtreeEnd - 1)
        }
        return first...last
    }

    /// 그 범위를 바꿔 쓰면 감춘 줄이 보이지 않는 채로 고쳐지는 접힌 토글들.
    ///
    /// 감춘 줄의 글자나 그 앞뒤 줄바꿈(제목 줄과 감춘 줄, 감춘 줄과 다음 줄을 잇는 것)에 닿으면 해당한다.
    /// 접힌 덩어리를 통째로 덮는 범위도 마찬가지다(보이지 않는 줄이 함께 지워지므로).
    static func brokenRoots(by range: NSRange, in doc: MarkdownDocument, folded: Set<Int>) -> Set<Int> {
        let lower = range.location
        let upper = NSMaxRange(range)
        return sanitized(folded, in: doc).filter { root in
            let title = doc.lines[doc.blockLines(at: root).upperBound]
            guard doc.lines[root].subtreeEnd > doc.blockLines(at: root).upperBound + 1 else { return false }
            let last = doc.lines[doc.lines[root].subtreeEnd - 1]
            return range.length == 0
                ? lower > title.end && lower <= last.end
                : lower < NSMaxRange(last.fullRange) && upper > title.end
        }
    }

    /// 원문이 바뀐 뒤의 접힌 줄 번호. 접힌 토글은 자기 줄의 첫 글자를 따라간다.
    ///
    /// - 줄이 바뀐 범위의 끝이나 그 뒤에서 시작하면, 그 첫 글자가 옮겨 간 줄이 된다
    ///   (위의 줄을 지우거나 더해도, 줄 맨 앞에 글자를 끼워도 따라간다).
    /// - 줄이 바뀐 범위의 시작이나 그 앞에서 시작하면 줄 번호가 그대로다.
    /// - 줄의 첫 글자가 바뀐 범위 한가운데에 있었으면 어디로 갔는지 알 수 없으므로 버린다.
    ///
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
        let editStart = min(editedRange.location, old.length)
        let oldEnd = max(editStart, min(old.length, NSMaxRange(editedRange) - delta))
        var result = Set<Int>()
        for index in folded where old.lines.indices.contains(index) {
            let start = old.lines[index].start
            if start >= oldEnd {
                result.insert(new.lineIndex(at: start + delta))
            } else if start <= editStart {
                result.insert(index)
            }
        }
        return sanitized(result, in: new)
    }

    /// 접기. 커서 줄이 토글이면 그 줄을, 아니면 그 줄을 품은 가장 가까운 토글을 접는다.
    static func fold(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> (folded: Set<Int>, selection: NSRange)? {
        let index = doc.blockLines(at: doc.lineIndex(at: selection.location)).lowerBound
        var target: Int?
        if doc.lines[index].kind.isToggle, !folded.contains(index) {
            target = index
        } else {
            target = (0..<index).reversed().first {
                doc.lines[$0].kind.isToggle && doc.lines[$0].subtreeEnd > index && !folded.contains($0)
            }
        }
        guard let target else { return nil }
        let title = doc.lines[target]
        guard title.subtreeEnd > doc.blockLines(at: target).upperBound + 1 else { return nil }
        let end = doc.lines[doc.blockLines(at: target).upperBound].end
        return (folded.union([target]), NSMaxRange(selection) > end ? NSRange(location: end, length: 0) : selection)
    }

    /// 펼치기. 커서 줄이 접힌 토글일 때만.
    static func unfold(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>) -> Set<Int>? {
        let index = doc.blockLines(at: doc.lineIndex(at: selection.location)).lowerBound
        guard folded.contains(index) else { return nil }
        return folded.subtracting([index])
    }
}
