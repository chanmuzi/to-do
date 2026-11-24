import Foundation

/// 링크 단축키가 고칠 대상.
nonisolated enum LinkTarget: Equatable, Sendable {
    /// 이미 있는 링크(`[글자](주소)`). 주소를 고치거나 링크를 벗긴다.
    case existing(InlineSpan)
    /// 링크로 만들 글자 범위.
    case new(NSRange)
}

nonisolated extension EditorCommands {
    /// 커서나 선택이 링크 안이면 그 링크, 아니면 선택한 글자. 링크를 걸 수 없으면 `nil`
    /// (선택 없음, 여러 줄, 코드 안, 다른 링크에 걸친 선택).
    static func linkTarget(_ doc: MarkdownDocument, selection: NSRange) -> LinkTarget? {
        guard let line = inlineLine(doc, selection) else { return nil }
        let isLink: (InlineSpan) -> Bool = { if case .link = $0.kind { true } else { false } }
        if let span = line.markedSpans.last(where: {
            isLink($0) && ($0.range == selection || ($0.contentRange.location <= selection.location && NSMaxRange(selection) <= NSMaxRange($0.contentRange)))
        }) {
            return .existing(span)
        }
        guard let visible = visibleSelection(selection, in: line),
              let outside = outsideCode(visible, in: line, allowsInside: false) else { return nil }
        // 고른 글자만 링크로 만든다. 글자가 통째로 든 구간은 기호까지 넣고, 한쪽만 걸친 구간은 넓히지 않는다
        // (넣을 때 그 구간을 링크 앞뒤에서 나눈다).
        var lower = outside.location
        var upper = NSMaxRange(outside)
        var changed = true
        while changed {
            changed = false
            // 선택을 통째로 안에 둔 구간은 그대로 둔다(링크가 그 구간 안에 들어간다).
            for span in line.hiddenSpans where !(span.contentRange.location <= lower && upper <= NSMaxRange(span.contentRange)) {
                if span.contentRange.location == lower, span.range.location < lower, NSMaxRange(span.contentRange) <= upper {
                    lower = span.range.location
                    changed = true
                }
                if NSMaxRange(span.contentRange) == upper, NSMaxRange(span.range) > upper, span.contentRange.location >= lower {
                    upper = NSMaxRange(span.range)
                    changed = true
                }
            }
        }
        let range = NSRange(location: lower, length: upper - lower)
        guard !line.markedSpans.contains(where: { isLink($0) && NSIntersectionRange($0.range, range).length > 0 }) else { return nil }
        // 코드 안에서는 백슬래시도 보이는 글자여서 닫는 대괄호를 이스케이프할 수 없다.
        guard !line.markedSpans.contains(where: { span in
            span.kind == .code && NSIntersectionRange(span.range, range).length > 0 && doc.string(in: span.contentRange).contains("]")
        }) else { return nil }
        return .new(range)
    }

    /// 주소 칸에 처음 보일 글자: 있는 링크는 그 주소, 고른 글자가 주소처럼 생겼으면 그 글자.
    static func linkAddress(_ doc: MarkdownDocument, for target: LinkTarget) -> String {
        switch target {
        case .existing(let span):
            if case .link(let url) = span.kind { return url }
            return ""
        case .new(let range):
            let text = doc.string(in: range)
            return text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("mailto:") ? text : ""
        }
    }

    /// 주소를 넣는다. 주소가 비어 있으면 있는 링크는 벗기고(글자만 남긴다), 새 링크는 만들지 않는다.
    static func setLink(_ doc: MarkdownDocument, target: LinkTarget, address: String) -> TextEdit? {
        let url = sanitizedAddress(address)
        switch target {
        case .existing(let span):
            let content = doc.string(in: span.contentRange)
            if url.isEmpty {
                return TextEdit(
                    range: span.range,
                    replacement: content,
                    selection: NSRange(location: span.range.location + content.utf16.count, length: 0)
                )
            }
            return TextEdit(
                range: span.closeMarker,
                replacement: "](\(url))",
                selection: NSRange(location: NSMaxRange(span.contentRange), length: 0)
            )
        case .new(let range):
            guard !url.isEmpty else { return nil }
            let text = escaped(doc.string(in: range), only: ["]"])
            let line = doc.line(at: range.location)
            // 링크의 한쪽 끝만 걸친 구간은 그 끝에서 닫고 건너편에서 다시 연다(구간이 링크의 기호와 엇갈리지 않게).
            func cut(at position: Int) -> [InlineSpan] {
                line.markedSpans.filter { span in
                    span.contentRange.location < position && position < NSMaxRange(span.contentRange)
                        && !(span.contentRange.location <= range.location && NSMaxRange(range) <= NSMaxRange(span.contentRange))
                }.sorted { $0.range.length < $1.range.length }
            }
            var pieces: [(text: String, isMarker: Bool)] = []
            let atStart = cut(at: range.location)
            let atEnd = cut(at: NSMaxRange(range))
            pieces += atStart.map { (doc.string(in: $0.closeMarker), true) }
            pieces.append(("[", true))
            pieces += atStart.reversed().map { (doc.string(in: $0.openMarker), true) }
            pieces.append((text, false))
            pieces += atEnd.map { (doc.string(in: $0.closeMarker), true) }
            let caret = pieces.reduce(0) { $0 + $1.text.utf16.count }
            pieces.append(("](\(url))", true))
            pieces += atEnd.reversed().map { (doc.string(in: $0.openMarker), true) }
            var markers: [NSRange] = []
            var offset = 0
            for piece in pieces {
                if piece.isMarker { markers.append(NSRange(location: offset, length: piece.text.utf16.count)) }
                offset += piece.text.utf16.count
            }
            let edit = TextEdit(
                range: range,
                replacement: pieces.map(\.text).joined(),
                selection: NSRange(location: range.location + caret, length: 0)
            )
            return marksAreRecognized(doc, edit, markers: markers) ? edit : nil
        }
    }

    /// 원문의 `(주소)` 자리에 넣을 수 있게 고친다: 앞뒤 공백을 떼고, 문법을 깨는 글자를 바꿔 적는다.
    static func sanitizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }
}
