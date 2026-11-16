import Foundation

// 인라인 기호는 화면에 보이지 않는다. 그래서 글을 지우거나 덮어쓸 때 기호가 짝을 잃거나
// 빈 구간(`****`)으로 남지 않게 원문을 함께 고친다.

nonisolated extension EditorCommands {
    /// 범위를 `text`로 바꿔 쓰는 편집. 그대로 바꿔 써도 되면 `nil`(텍스트 뷰의 기본 동작에 맡긴다).
    ///
    /// - 보이는 글자가 모두 지워지는 구간은 기호까지 지운다.
    /// - 한쪽 기호만 범위에 든 구간은 그 기호를 남긴다(닫는 기호는 넣는 글 앞에, 여는 기호는 뒤에).
    /// - 줄바꿈이 든 글을 구간 안에 넣으면 구간을 줄바꿈 앞에서 닫고 뒤에서 다시 연다
    ///   (구간은 줄을 넘지 못한다).
    static func replacing(_ doc: MarkdownDocument, _ range: NSRange, with text: String) -> TextEdit? {
        let isMultiline = text.contains("\n")
        guard range.length > 0 || isMultiline else { return nil }
        var lower = range.location
        var upper = NSMaxRange(range)
        let lines = doc.lineIndex(at: lower)...doc.lineIndex(at: upper)
        let spans = lines.flatMap { doc.lines[$0].hiddenSpans }
        guard !spans.isEmpty else { return nil }

        // 기호 한가운데에서 끝나는 범위는 그 기호를 통째로 넣는다.
        for span in spans {
            for marker in [span.openMarker, span.closeMarker] where marker.length > 0 {
                if marker.location < lower, lower < NSMaxRange(marker) { lower = marker.location }
                if marker.location < upper, upper < NSMaxRange(marker) { upper = NSMaxRange(marker) }
            }
        }

        func covers(_ inner: NSRange) -> Bool { lower <= inner.location && NSMaxRange(inner) <= upper }
        func isWithin(_ outer: NSRange) -> Bool { outer.location <= lower && upper <= NSMaxRange(outer) }

        // 글자가 모두 지워지는 구간은 기호까지 지운다. 넣는 글이 그 구간 안에 놓이면 구간은 남는다.
        var changed = true
        while changed {
            changed = false
            for span in spans where covers(span.contentRange) && !covers(span.range) {
                // 백슬래시로 막은 글자는 글자가 바뀌면 백슬래시도 함께 지운다.
                if !text.isEmpty, !isMultiline, isWithin(span.contentRange), span.kind != .escape { continue }
                lower = min(lower, span.range.location)
                upper = max(upper, NSMaxRange(span.range))
                changed = true
            }
        }

        // 줄바꿈이 든 글: 범위를 안에 둔 구간을 나눈다. 안쪽 구간부터.
        var closesBefore = ""
        var opensAfter = ""
        var spaceBefore = ""
        var spaceAfter = ""
        var split: Set<InlineSpan> = []
        if isMultiline {
            for span in spans.sorted(by: { $0.range.length < $1.range.length })
            where isWithin(span.contentRange) && span.kind != .escape {
                split.insert(span)
                let open = doc.string(in: span.openMarker)
                let close = doc.string(in: span.closeMarker)
                let leftIsEmpty = lower == span.contentRange.location
                let rightIsEmpty = upper == NSMaxRange(span.contentRange)
                if leftIsEmpty {
                    lower = span.range.location
                } else {
                    closesBefore += close
                }
                if rightIsEmpty {
                    upper = NSMaxRange(span.range)
                } else {
                    opensAfter = open + opensAfter
                }
            }
        }

        // 한쪽 기호만 범위에 든 구간의 기호를 남긴다.
        var closes = ""
        var opens = ""
        for span in spans.sorted(by: { $0.range.location < $1.range.location }) where !split.contains(span) && !covers(span.range) {
            if span.openMarker.length > 0, covers(span.openMarker) { opens += doc.string(in: span.openMarker) }
        }
        for span in spans.sorted(by: { NSMaxRange($0.range) < NSMaxRange($1.range) }) where !split.contains(span) && !covers(span.range) {
            if span.closeMarker.length > 0, covers(span.closeMarker) { closes += doc.string(in: span.closeMarker) }
        }

        // 닫는 기호 앞과 여는 기호 뒤는 공백일 수 없다. 기호가 놓일 자리에 닿은 공백은 기호 밖으로 낸다.
        // 링크의 글자는 공백으로 시작하거나 끝나도 되므로, 링크의 기호만 걸린 자리는 그대로 둔다.
        let touchesLink = spans.contains { span in
            guard case .link = span.kind else { return false }
            return !covers(span.range) && (covers(span.openMarker) || covers(span.closeMarker) || split.contains(span))
        }
        if !touchesLink, !closes.isEmpty || !closesBefore.isEmpty {
            var start = lower
            while start > 0, InlineParser.isWhitespace(doc.units[start - 1]) { start -= 1 }
            spaceBefore = doc.string(in: NSRange(location: start, length: lower - start))
            lower = start
        }
        if !touchesLink, !opens.isEmpty || !opensAfter.isEmpty {
            var end = upper
            while end < doc.length, InlineParser.isWhitespace(doc.units[end]) { end += 1 }
            // 줄바꿈으로 끝나는 글 뒤의 공백은 버린다(새 줄의 맨 앞이 된다).
            if !text.hasSuffix("\n") { spaceAfter = doc.string(in: NSRange(location: upper, length: end - upper)) }
            upper = end
        }
        let head = closes + closesBefore + spaceBefore + text + spaceAfter
        let replacement = head + opensAfter + opens
        let result = NSRange(location: lower, length: upper - lower)
        if result == range, replacement == text { return nil }
        return TextEdit(
            range: result,
            replacement: replacement,
            selection: NSRange(location: lower + head.utf16.count + opensAfter.utf16.count, length: 0)
        )
    }

    /// `replacing`을 거친 편집. 고칠 것이 없으면 그대로 넣는 편집을 돌려준다.
    static func insert(_ doc: MarkdownDocument, _ text: String, replacing range: NSRange) -> TextEdit {
        replacing(doc, range, with: text) ?? .insert(text, replacing: range)
    }

    /// 그 범위를 지우면 코드 블록의 ``` 줄이 깨지는지. ``` 줄은 보이지 않으므로 사용자가 일부러
    /// 지울 수 없고, 한쪽만 지워지면 그 아래의 글이 모두 코드로(또는 코드가 글로) 뒤집힌다.
    /// 블록을 통째로 덮는 범위는 괜찮다.
    static func breaksCodeFence(_ doc: MarkdownDocument, _ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let lower = range.location
        let upper = NSMaxRange(range)
        var index = doc.lineIndex(at: max(0, lower - 1))
        let lastIndex = min(doc.lines.count - 1, doc.lineIndex(at: upper) + 1)
        while index <= lastIndex {
            let line = doc.lines[index]
            guard let block = line.codeBlock else {
                index += 1
                continue
            }
            let open = doc.lines[block.lowerBound]
            let last = doc.lines[block.upperBound]
            let whole = NSRange(location: open.start, length: last.end - open.start)
            if !(lower <= whole.location && NSMaxRange(whole) <= upper) {
                // 여는 줄: 앞의 줄바꿈부터 여는 줄의 줄바꿈까지.
                var zones = [NSRange(location: max(0, open.start - 1), length: NSMaxRange(open.fullRange) - max(0, open.start - 1))]
                if last.kind == .fenceClose, block.upperBound > block.lowerBound {
                    // 닫는 줄: 앞의 줄바꿈부터 닫는 줄의 줄바꿈까지.
                    zones.append(NSRange(location: last.start - 1, length: NSMaxRange(last.fullRange) - last.start + 1))
                }
                if zones.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return true }
            }
            index = block.upperBound + 1
        }
        return false
    }
}
