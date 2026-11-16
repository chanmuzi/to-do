import Foundation

nonisolated extension EditorCommands {
    enum Wrap: Sendable {
        case bold, strike, code

        var marker: String {
            switch self {
            case .bold: "**"
            case .strike: "~~"
            case .code: "`"
            }
        }

        func matches(_ kind: InlineSpan.Kind) -> Bool {
            switch (self, kind) {
            case (.bold, .bold), (.strike, .strike), (.code, .code): true
            default: false
            }
        }
    }

    /// 굵게, 취소선, 인라인 코드. 이미 그 서식 안이면 벗긴다. 여러 줄 선택에는 쓰지 않는다.
    static func toggleWrap(_ doc: MarkdownDocument, selection: NSRange, _ wrap: Wrap) -> TextEdit? {
        guard let line = inlineLine(doc, selection) else { return nil }
        if let span = line.spans.last(where: { wrap.matches($0.kind) && $0.contains(selection) }) {
            return unwrapping(doc, span, selection: selection)
        }
        return wrapping(doc, selection, open: wrap.marker, close: wrap.marker)
    }

    /// 형광펜. 누를 때마다 노랑, 회색, 로즈, 블루로 넘어가고 그다음에는 지운다.
    static func cycleHighlight(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard let line = inlineLine(doc, selection) else { return nil }
        for span in line.spans.reversed() where span.contains(selection) {
            guard case .highlight(let number) = span.kind else { continue }
            if number >= 4 { return unwrapping(doc, span, selection: selection) }
            let content = doc.string(in: span.contentRange)
            let limit = NSMaxRange(span.contentRange)
            let start = min(selection.location, limit)
            let end = min(NSMaxRange(selection), limit)
            return TextEdit(
                range: span.range,
                replacement: "==" + content + "=={\(number + 1)}",
                selection: NSRange(location: start, length: end - start)
            )
        }
        return wrapping(doc, selection, open: "==", close: "==")
    }

    /// 링크. 선택한 글자가 주소면 주소 자리에, 아니면 글자 자리에 넣는다.
    static func link(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard let line = inlineLine(doc, selection) else { return nil }
        if let span = line.spans.last(where: { span in
            if case .link = span.kind { span.openMarker.length > 0 && span.contains(selection) } else { false }
        }) {
            return unwrapping(doc, span, selection: selection)
        }
        let selected = doc.string(in: selection)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return TextEdit(range: selection, replacement: "[](\(selected))", selection: NSRange(location: selection.location + 1, length: 0))
        }
        return TextEdit(
            range: selection,
            replacement: "[\(selected)]()",
            selection: NSRange(location: selection.location + (selected.isEmpty ? 1 : selection.length + 3), length: 0)
        )
    }

    /// 선택이 한 줄 안에 있고 그 줄이 코드가 아닐 때만 그 줄.
    private static func inlineLine(_ doc: MarkdownDocument, _ selection: NSRange) -> MarkdownLine? {
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        guard doc.lineIndex(at: NSMaxRange(selection)) == index, !line.kind.isCode else { return nil }
        return line
    }

    private static func wrapping(_ doc: MarkdownDocument, _ selection: NSRange, open: String, close: String) -> TextEdit {
        TextEdit(
            range: selection,
            replacement: open + doc.string(in: selection) + close,
            selection: NSRange(location: selection.location + open.utf16.count, length: selection.length)
        )
    }

    private static func unwrapping(_ doc: MarkdownDocument, _ span: InlineSpan, selection: NSRange) -> TextEdit {
        let content = span.contentRange
        func moved(_ position: Int) -> Int {
            min(max(position, content.location), NSMaxRange(content)) - span.openMarker.length
        }
        let start = moved(selection.location)
        return TextEdit(
            range: span.range,
            replacement: doc.string(in: content),
            selection: NSRange(location: start, length: moved(NSMaxRange(selection)) - start)
        )
    }
}
