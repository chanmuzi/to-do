import Foundation

/// 커서가 감춰 둔 곳(줄 머리의 기호, 접힌 줄)에 놓이지 않게 옮긴다.
nonisolated enum CaretSnapping {
    /// - Parameters:
    ///   - old: 옮기기 전의 선택.
    ///   - new: 옮기려는 선택. 길이가 있으면 그대로 둔다.
    static func snap(old: NSRange, new: NSRange, in doc: MarkdownDocument, folded: Set<Int>) -> NSRange {
        guard new.length == 0 else { return snapSelection(old: old, new: new, in: doc) }
        let index = doc.lineIndex(at: new.location)
        let forward = new.location > old.location

        // 접힌 줄 안: 앞으로 가는 중이면 접힌 덩어리 다음 줄로, 아니면 토글 제목 끝으로.
        if let root = FoldState.foldRoot(of: index, in: doc, folded: folded) {
            let title = doc.lines[root]
            if forward, title.subtreeEnd < doc.lines.count {
                return NSRange(location: doc.lines[title.subtreeEnd].caretStart, length: 0)
            }
            return NSRange(location: title.end, length: 0)
        }

        let line = doc.lines[index]
        guard new.location < line.caretStart else { return new }
        // 줄 머리 바로 뒤에서 왼쪽으로 가면 윗줄 끝으로 넘어간다.
        if !forward, old.length == 0, old.location == line.caretStart, index > 0 {
            let previous = FoldState.foldRoot(of: index - 1, in: doc, folded: folded) ?? index - 1
            return NSRange(location: doc.lines[previous].end, length: 0)
        }
        return NSRange(location: line.caretStart, length: 0)
    }

    /// 선택의 끝이 감춘 줄 머리 한가운데에 걸리지 않게 한다. 줄 머리는 통째로 들어가거나 통째로 빠진다
    /// (기호의 일부만 지워져 깨진 문법이 남지 않게).
    private static func snapSelection(old: NSRange, new: NSRange, in doc: MarkdownDocument) -> NSRange {
        func snapped(_ position: Int, movedBack: Bool) -> Int {
            let line = doc.lines[doc.lineIndex(at: position)]
            guard position > line.start, position < line.caretStart else { return position }
            return movedBack ? line.start : line.caretStart
        }
        let start = snapped(new.location, movedBack: new.location < old.location)
        let end = max(start, snapped(NSMaxRange(new), movedBack: NSMaxRange(new) < NSMaxRange(old)))
        return NSRange(location: start, length: end - start)
    }
}
