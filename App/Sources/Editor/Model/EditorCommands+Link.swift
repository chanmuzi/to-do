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
    /// (선택 없음, 여러 줄, 코드 안, 대괄호가 든 글, 다른 링크에 걸친 선택).
    static func linkTarget(_ doc: MarkdownDocument, selection: NSRange) -> LinkTarget? {
        guard let line = inlineLine(doc, selection) else { return nil }
        let isLink: (InlineSpan) -> Bool = { if case .link = $0.kind { true } else { false } }
        if let span = line.markedSpans.last(where: {
            isLink($0) && $0.contentRange.location <= selection.location && NSMaxRange(selection) <= NSMaxRange($0.contentRange)
        }) {
            return .existing(span)
        }
        guard let visible = visibleSelection(selection, in: line),
              let outside = outsideCode(visible, in: line, allowsInside: false) else { return nil }
        let range = balanced(outside, in: line)
        guard !line.markedSpans.contains(where: { isLink($0) && NSIntersectionRange($0.range, range).length > 0 }) else { return nil }
        let text = doc.string(in: range)
        guard !text.contains("["), !text.contains("]") else { return nil }
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
            let text = doc.string(in: range)
            return TextEdit(
                range: range,
                replacement: "[\(text)](\(url))",
                selection: NSRange(location: range.location + 1 + text.utf16.count, length: 0)
            )
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
