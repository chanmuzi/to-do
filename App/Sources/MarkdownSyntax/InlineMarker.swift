import Foundation

/// 줄 안에서 화면에 보이지 않는 인라인 기호 하나(`**`, `~~`, `==`, `=={2}`, `` ` ``, `[`, `](주소)`).
nonisolated package struct InlineMarker: Hashable, Sendable {
    package var range: NSRange
    /// 여는 기호면 `true`, 닫는 기호면 `false`.
    package var isOpen: Bool
    package var span: InlineSpan
}

// 감춘 기호는 너비가 없다. 같은 자리에 겹쳐 보이는 원문 위치들 사이를 오가는 데 쓰는 계산이다.
nonisolated package extension MarkdownLine {
    /// 기호가 있는 서식 구간(주소만 적은 링크는 기호가 없다). 백슬래시로 막은 글자는 서식이 아니므로 뺀다.
    var markedSpans: [InlineSpan] {
        spans.filter { $0.range.length > $0.contentRange.length && $0.kind != .escape }
    }

    /// 감춘 글자가 있는 구간 모두(서식 구간과 백슬래시로 막은 글자).
    var hiddenSpans: [InlineSpan] {
        spans.filter { $0.range.length > $0.contentRange.length }
    }

    /// 백슬래시로 막은 글자들.
    var escapes: [InlineSpan] {
        spans.filter { $0.kind == .escape }
    }

    /// 그 위치가 백슬래시와 그것이 막은 글자 사이면 그 구간. 커서와 편집의 경계는 여기에 놓이지 않는다.
    func escape(splitAt position: Int) -> InlineSpan? {
        spans.first { $0.kind == .escape && $0.contentRange.location == position }
    }

    /// 감춘 기호들. 앞에서부터.
    var markers: [InlineMarker] {
        var result: [InlineMarker] = []
        for span in hiddenSpans {
            if span.openMarker.length > 0 { result.append(InlineMarker(range: span.openMarker, isOpen: true, span: span)) }
            if span.closeMarker.length > 0 { result.append(InlineMarker(range: span.closeMarker, isOpen: false, span: span)) }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    func marker(startingAt position: Int) -> InlineMarker? {
        markers.first { $0.range.location == position }
    }

    func marker(endingAt position: Int) -> InlineMarker? {
        markers.first { NSMaxRange($0.range) == position }
    }

    /// 그 위치가 기호 한가운데면 그 기호.
    func marker(enclosing position: Int) -> InlineMarker? {
        markers.first { $0.range.location < position && position < NSMaxRange($0.range) }
    }

    /// 그 위치에서 시작해 잇달아 놓인 기호들을 지난 곳. 기호 한가운데면 그 기호 끝부터 센다.
    func visualEnd(from position: Int) -> Int {
        let all = markers
        var result = all.first { $0.range.location < position && position < NSMaxRange($0.range) }
            .map { NSMaxRange($0.range) } ?? position
        while let next = all.first(where: { $0.range.location == result }) { result = NSMaxRange(next.range) }
        return result
    }

    /// 그 위치 앞에 잇달아 놓인 기호들의 맨 앞. 기호 한가운데면 그 기호 앞부터 센다.
    func visualStart(from position: Int) -> Int {
        let all = markers
        var result = all.first { $0.range.location < position && position < NSMaxRange($0.range) }
            .map(\.range.location) ?? position
        while let previous = all.first(where: { NSMaxRange($0.range) == result }) { result = previous.range.location }
        return result
    }

    /// 글자가 보이기 시작하는 자리인지: 줄 머리 바로 뒤이거나, 그 사이에 감춘 여는 기호만 있다.
    func isVisualStart(_ position: Int) -> Bool {
        position >= contentStart && position <= visualEnd(from: contentStart) && marker(enclosing: position) == nil
    }

    /// 글자가 끝나는 자리인지: 줄 끝이거나, 줄 끝까지 감춘 닫는 기호만 있다.
    func isVisualEnd(_ position: Int) -> Bool {
        position <= contentEnd && visualEnd(from: position) == (inkComment?.location ?? end)
    }

    /// 그 위치를 안에 둔 구간들(구간의 글자 맨 앞과 맨 끝도 안이다). 안쪽 것부터.
    func spansContaining(_ position: Int) -> [InlineSpan] {
        markedSpans
            .filter { $0.contentRange.location <= position && position <= NSMaxRange($0.contentRange) }
            .sorted { $0.range.length < $1.range.length }
    }

    /// 두 위치 사이의 글자가 모두 감춘 기호인지(사이가 비어 있으면 `false`).
    func isHiddenOnly(from a: Int, to b: Int) -> Bool {
        let lower = min(a, b)
        let upper = max(a, b)
        guard lower < upper, lower >= contentStart, upper <= end else { return false }
        var position = lower
        let all = markers
        while position < upper {
            guard let next = all.first(where: { $0.range.location <= position && position < NSMaxRange($0.range) }) else { return false }
            position = NSMaxRange(next.range)
        }
        return true
    }
}

nonisolated package extension MarkdownDocument {
    func closingSyntax(for span: InlineSpan) -> String {
        if case .highlight(let id) = span.kind, let color = InkColor.byID[id] { return "=={" + color.suffix + "}" }
        return string(in: span.closeMarker)
    }

    func line(at location: Int) -> MarkdownLine {
        lines[lineIndex(at: location)]
    }

    /// 그 위치에서 시작하는 글자 하나(이모지, 조합된 글자는 통째로)의 범위.
    func characterRange(at location: Int) -> NSRange {
        guard location >= 0, location < length else { return NSRange(location: min(max(location, 0), length), length: 0) }
        return (text as NSString).rangeOfComposedCharacterSequence(at: location)
    }

    /// 그 위치 바로 앞 글자 하나의 범위.
    func characterRange(before location: Int) -> NSRange {
        guard location > 0 else { return NSRange(location: 0, length: 0) }
        return (text as NSString).rangeOfComposedCharacterSequence(at: min(location, length) - 1)
    }
}
