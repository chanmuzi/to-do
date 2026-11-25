import Foundation

/// 커서가 감춰 둔 곳(줄 머리의 기호, 접힌 줄, 코드 블록의 ``` 줄, 인라인 기호)에 놓이지 않게 옮긴다.
///
/// 인라인 기호의 규칙(D-036):
/// 1. 감춘 기호는 너비가 없으므로 서식 구간의 양 끝에는 같은 자리에 보이는 원문 위치가 둘씩 있다
///    (기호 바깥, 기호 안). 커서는 기호 한가운데에는 놓이지 않는다.
/// 2. 구간의 끝에서는 안쪽이 기본이다(이어 치면 서식이 이어진다). 구간의 앞에서는 바깥쪽이 기본이고
///    (이어 치면 서식이 없다), 줄의 맨 앞에서만 안쪽이다.
/// 3. →, ←는 기호를 건너뛰고 보이는 글자 하나를 지난다. 다만 구간 끝의 안쪽에서 →를 누르면 자리는
///    그대로인 채 구간 밖으로 나가고(그 뒤에 치는 글자는 서식이 없다), 줄 맨 앞의 안쪽에서 ←도 같다.
/// 4. 선택의 양 끝은 보이는 글자에 붙는다(시작은 기호 뒤, 끝은 기호 앞).
nonisolated enum CaretSnapping {
    /// - Parameters:
    ///   - old: 옮기기 전의 선택.
    ///   - new: 옮기려는 선택. 길이가 있으면 양 끝을 따로 옮긴다.
    ///   - textChanged: 원문이 바뀌어서 따라온 선택이다. 놓일 수 없는 자리만 고치고 그 밖에는 그대로 둔다.
    static func snap(
        old: NSRange,
        new: NSRange,
        in doc: MarkdownDocument,
        folded: Set<Int>,
        textChanged: Bool = false
    ) -> NSRange {
        guard new.length == 0 else {
            return snapSelection(old: old, new: new, in: doc, folded: folded, textChanged: textChanged)
        }
        let forward = new.location > old.location
        var position = new.location
        // 줄 단위로 감춘 곳을 벗어난다. 벗어난 자리가 또 감춘 줄일 수 있어 몇 번 되풀이한다.
        for _ in 0..<8 {
            let next = visibleLinePosition(position, old: old, forward: forward, in: doc, folded: folded)
            if next == position { break }
            position = next
        }
        let line = doc.line(at: position)
        guard !line.kind.isCode, position >= line.contentStart else { return NSRange(location: position, length: 0) }
        if textChanged {
            if line.marker(enclosing: position) != nil { position = canonical(position, in: line) }
            if let escape = line.escape(splitAt: position) { position = escape.range.location }
            return NSRange(location: position, length: 0)
        }
        if position == new.location, old.length == 0, old.location != position,
           doc.lineIndex(at: old.location) == doc.lineIndex(at: position),
           line.isHiddenOnly(from: old.location, to: position) {
            position = forward
                ? stepForward(from: old.location, in: line, doc)
                : stepBackward(from: old.location, in: line, doc)
        } else {
            position = canonical(position, in: line)
        }
        return NSRange(location: position, length: 0)
    }

    /// 같은 자리에 겹쳐 보이는 위치들 가운데 기본 자리(규칙 2).
    static func canonical(_ position: Int, in line: MarkdownLine) -> Int {
        let first = line.visualStart(from: position)
        let last = line.visualEnd(from: position)
        guard first != last else { return position }
        let result = first > line.contentStart ? first : last
        // 백슬래시와 그것이 막은 글자 사이에는 놓이지 않는다. 백슬래시 앞이 그 글자의 앞이다.
        return line.escape(splitAt: result)?.range.location ?? result
    }

    // MARK: 인라인 기호

    private static func stepForward(from position: Int, in line: MarkdownLine, _ doc: MarkdownDocument) -> Int {
        // 구간 끝의 안쪽: 닫는 기호들만 지나 밖으로 나간다.
        if let marker = line.marker(startingAt: position), !marker.isOpen {
            var result = position
            while let close = line.marker(startingAt: result), !close.isOpen { result = NSMaxRange(close.range) }
            return result
        }
        let visible = line.visualEnd(from: position)
        guard visible < line.end else { return visible }
        let next = NSMaxRange(doc.characterRange(at: visible))
        return line.escape(splitAt: next)?.range.location ?? next
    }

    private static func stepBackward(from position: Int, in line: MarkdownLine, _ doc: MarkdownDocument) -> Int {
        // 구간 앞의 안쪽: 여는 기호들만 지나 밖으로 나간다.
        if let marker = line.marker(endingAt: position), marker.isOpen {
            var result = position
            while let open = line.marker(endingAt: result), open.isOpen { result = open.range.location }
            return result
        }
        let visible = line.visualStart(from: position)
        guard visible > line.contentStart else { return visible }
        return canonical(doc.characterRange(before: visible).location, in: line)
    }

    // MARK: 줄

    /// 접힌 줄, ``` 줄, 줄 머리 안의 위치를 보이는 곳으로 한 번 옮긴다. 옮길 것이 없으면 그대로 돌려준다.
    private static func visibleLinePosition(
        _ position: Int,
        old: NSRange,
        forward: Bool,
        in doc: MarkdownDocument,
        folded: Set<Int>
    ) -> Int {
        let index = doc.lineIndex(at: position)

        // 접힌 줄 안: 앞으로 가는 중이면 접힌 덩어리 다음 줄로, 아니면 토글 제목 끝으로.
        if let root = FoldState.foldRoot(of: index, in: doc, folded: folded) {
            let title = doc.lines[root]
            if forward, title.subtreeEnd < doc.lines.count { return doc.lines[title.subtreeEnd].caretStart }
            return title.end
        }

        let line = doc.lines[index]
        if line.hasHardBreak, position == line.end {
            return forward && old.location == line.contentEnd ? doc.lines[index + 1].caretStart : line.contentEnd
        }
        if line.kind == .fenceOpen || line.kind == .fenceClose {
            // 줄이 없는 블록에는 커서 자리가 하나 있다(`EditorCommands.emptyBlockCaret`).
            if let block = EditorCommands.emptyBlock(doc, at: index) {
                let spot = EditorCommands.emptyBlockCaret(doc, block)
                if position == spot { return position }
                if old.length > 0 || old.location != spot { return spot }
                // 그 자리에서 나가는 길.
                if forward, block.upperBound + 1 < doc.lines.count { return doc.lines[block.upperBound + 1].caretStart }
                if !forward, block.lowerBound > 0 { return previousLineEnd(block.lowerBound, in: doc, folded: folded) }
                return spot
            }
            return fencePosition(index, old: old, forward: forward, in: doc, folded: folded)
        }

        guard position < line.caretStart else { return position }
        // 줄 머리 바로 뒤에서 왼쪽으로 가면 윗줄 끝으로 넘어간다.
        if !forward, old.length == 0, old.location == line.caretStart, index > 0 {
            return previousLineEnd(index, in: doc, folded: folded)
        }
        return line.caretStart
    }

    private static func previousLineEnd(_ index: Int, in doc: MarkdownDocument, folded: Set<Int>) -> Int {
        let previous = FoldState.foldRoot(of: index - 1, in: doc, folded: folded) ?? index - 1
        return doc.lines[previous].contentEnd
    }

    /// ``` 줄은 보이지 않는다. 블록 안에서 나오는 길이면 블록 밖의 이웃 줄로, 밖에서 들어오는 길이면
    /// 블록의 첫 줄(여는 줄)이나 마지막 줄(닫는 줄)로 보낸다.
    private static func fencePosition(
        _ index: Int,
        old: NSRange,
        forward: Bool,
        in doc: MarkdownDocument,
        folded: Set<Int>
    ) -> Int {
        let line = doc.lines[index]
        let block = line.codeBlock ?? index...index
        let code = block.filter { doc.lines[$0].kind == .code }
        let oldIndex = doc.lineIndex(at: old.location)
        let cameFromInside = block.contains(oldIndex) && doc.lines[oldIndex].kind == .code
        let hasNext = block.upperBound + 1 < doc.lines.count

        if line.kind == .fenceOpen {
            if cameFromInside {
                return index > 0 ? previousLineEnd(index, in: doc, folded: folded) : old.location
            }
            if let first = code.first { return doc.lines[first].caretStart }
        } else {
            if cameFromInside {
                return hasNext ? doc.lines[block.upperBound + 1].caretStart : old.location
            }
            if let last = code.last { return doc.lines[last].end }
        }
        // 줄이 하나도 없는 블록은 지나친다.
        if forward, hasNext { return doc.lines[block.upperBound + 1].caretStart }
        if block.lowerBound > 0 { return previousLineEnd(block.lowerBound, in: doc, folded: folded) }
        return hasNext ? doc.lines[block.upperBound + 1].caretStart : old.location
    }

    // MARK: 선택

    /// 선택의 끝이 감춘 줄 머리 한가운데나 접힌 줄 안에 걸리지 않게 한다.
    /// 줄 머리는 통째로 들어가거나 통째로 빠진다(기호의 일부만 지워져 깨진 문법이 남지 않게).
    /// 접힌 줄 안의 끝은 접힌 덩어리의 경계(토글 제목 끝, 또는 덩어리 다음 줄의 맨 앞)로 옮긴다.
    /// 그래서 접힌 덩어리는 선택에 통째로 들어가거나 통째로 빠진다. 코드 블록도 같다: 블록 안에서
    /// 시작해 밖으로 나가는 선택은 블록을 통째로 넣는다(``` 줄의 한쪽만 지워지지 않게).
    private static func snapSelection(
        old: NSRange,
        new: NSRange,
        in doc: MarkdownDocument,
        folded: Set<Int>,
        textChanged: Bool
    ) -> NSRange {
        func snapped(_ position: Int, movedBack: Bool) -> Int {
            let index = doc.lineIndex(at: position)
            if let root = FoldState.foldRoot(of: index, in: doc, folded: folded) {
                let title = doc.lines[root]
                if !movedBack, title.subtreeEnd < doc.lines.count { return doc.lines[title.subtreeEnd].start }
                return title.end
            }
            let line = doc.lines[index]
            guard position > line.start, position < line.caretStart else { return position }
            return movedBack ? line.start : line.caretStart
        }
        var start = snapped(new.location, movedBack: new.location < old.location)
        var end = max(start, snapped(NSMaxRange(new), movedBack: NSMaxRange(new) < NSMaxRange(old)))
        (start, end) = codeBlockAdjusted(start: start, end: end, old: old, new: new, in: doc)

        if textChanged {
            if let marker = doc.line(at: start).marker(enclosing: start) { start = marker.range.location }
            if let marker = doc.line(at: end).marker(enclosing: end) { end = NSMaxRange(marker.range) }
            guard end > start else { return NSRange(location: collapsed(start, in: doc), length: 0) }
            return NSRange(location: start, length: end - start)
        }

        // 한쪽 끝만 움직였고 지난 것이 감춘 기호뿐이면, 기호를 건너뛰고 보이는 글자 하나를 지난다.
        let oldEnd = NSMaxRange(old)
        if start == old.location, end != oldEnd {
            end = steppedEnd(from: oldEnd, to: end, in: doc)
        } else if end == oldEnd, start != old.location {
            start = steppedEnd(from: old.location, to: start, in: doc)
        }
        // 양 끝을 보이는 글자에 붙인다.
        let startLine = doc.line(at: start)
        if !startLine.kind.isCode, start >= startLine.contentStart {
            start = startLine.visualEnd(from: start)
            // 백슬래시로 막은 글자는 백슬래시째로 고른다.
            if let escape = startLine.escape(splitAt: start) { start = escape.range.location }
        }
        let endLine = doc.line(at: end)
        if !endLine.kind.isCode, end >= endLine.contentStart { end = endLine.visualStart(from: end) }
        guard end > start else {
            let line = doc.line(at: start)
            let position = line.kind.isCode || start < line.contentStart ? collapsed(start, in: doc) : canonical(start, in: line)
            return NSRange(location: position, length: 0)
        }
        return NSRange(location: start, length: end - start)
    }

    /// 선택이 줄어 커서가 되었을 때의 자리. 줄 맨 앞(감춘 줄 머리의 앞)은 선택의 끝으로만 쓰는 자리여서
    /// 커서는 그 줄의 보이는 시작으로 옮긴다(줄 종류를 바꾼 뒤 ⇧←로 선택이 줄 머리 안에서 접히는 경우, #9).
    /// 코드 블록의 ``` 줄은 따로 다룬다(`fencePosition`).
    private static func collapsed(_ position: Int, in doc: MarkdownDocument) -> Int {
        let line = doc.line(at: position)
        guard line.kind != .fenceOpen, line.kind != .fenceClose, position < line.caretStart else { return position }
        return line.caretStart
    }

    private static func steppedEnd(from old: Int, to new: Int, in doc: MarkdownDocument) -> Int {
        let line = doc.line(at: new)
        guard !line.kind.isCode, doc.lineIndex(at: old) == doc.lineIndex(at: new),
              line.isHiddenOnly(from: old, to: new) else { return new }
        if new > old {
            let visible = line.visualEnd(from: old)
            return visible < line.end ? NSMaxRange(doc.characterRange(at: visible)) : visible
        }
        let visible = line.visualStart(from: old)
        return visible > line.contentStart ? doc.characterRange(before: visible).location : visible
    }

    private static func codeBlockAdjusted(
        start: Int,
        end: Int,
        old: NSRange,
        new: NSRange,
        in doc: MarkdownDocument
    ) -> (Int, Int) {
        let startIndex = doc.lineIndex(at: start)
        let endIndex = doc.lineIndex(at: end)
        let startBlock = doc.lines[startIndex].codeBlock
        let endBlock = doc.lines[endIndex].codeBlock
        guard startBlock != nil || endBlock != nil else { return (start, end) }

        func blockStart(_ block: ClosedRange<Int>) -> Int { doc.lines[block.lowerBound].start }
        func blockEnd(_ block: ClosedRange<Int>) -> Int {
            block.upperBound + 1 < doc.lines.count ? doc.lines[block.upperBound + 1].start : doc.lines[block.upperBound].end
        }

        if startBlock == endBlock, let block = startBlock {
            // 블록을 통째로 덮는 선택(모두 선택)은 ``` 줄까지 넣는다.
            if new.location <= blockStart(block), NSMaxRange(new) >= doc.lines[block.upperBound].end {
                return (blockStart(block), blockEnd(block))
            }
            let code = block.filter { doc.lines[$0].kind == .code }
            guard let first = code.first, let last = code.last else { return (blockStart(block), blockEnd(block)) }
            var s = start
            var e = end
            if doc.lines[startIndex].kind != .code {
                s = startIndex <= first ? doc.lines[first].caretStart : doc.lines[last].end
            }
            if doc.lines[endIndex].kind != .code {
                e = endIndex >= last ? doc.lines[last].end : doc.lines[first].caretStart
            }
            e = max(s, e)
            // 블록의 끝에서 더 넓히려는데 나아가지 못했으면 블록을 통째로 고른다.
            if s == old.location, e == NSMaxRange(old), new != old, (s, e) != (start, end) {
                return (blockStart(block), blockEnd(block))
            }
            return (s, e)
        }

        var s = start
        var e = end
        if let block = startBlock {
            let line = doc.lines[startIndex]
            if line.kind == .fenceClose, s == line.end, startIndex + 1 < doc.lines.count {
                s = doc.lines[startIndex + 1].start
            } else {
                s = blockStart(block)
            }
        }
        if let block = endBlock, e != blockStart(block) { e = blockEnd(block) }
        return (s, max(s, e))
    }
}
