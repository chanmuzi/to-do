import Foundation

// 선택한 글에 서식을 입히고 벗긴다. 기호는 화면에 보이지 않으므로, 선택이 다른 구간에 걸쳐 있어도
// 원문의 기호가 엇갈리지 않게 맞춘다. 선택이 없을 때의 서식 켜고 끄기는 `TypingMarks`가 맡는다.

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

    /// 굵게, 취소선, 인라인 코드. 선택이 이미 그 서식 안이면 선택한 부분만 벗긴다.
    /// 여러 줄 선택과 코드 블록 안에서는 쓰지 않는다. 선택이 없으면 `nil`(`toggleTyping`을 쓴다).
    static func toggleWrap(_ doc: MarkdownDocument, selection: NSRange, _ wrap: Wrap) -> TextEdit? {
        guard let line = inlineLine(doc, selection), let selected = visibleSelection(selection, in: line) else { return nil }
        if let span = line.markedSpans.last(where: { wrap.matches($0.kind) && contains($0.contentRange, selected) }) {
            return resplit(doc, line, span, selected, open: "", close: "")
        }
        return wrapping(doc, line, selected, open: wrap.marker, close: wrap.marker) { kind in
            wrap == .code ? true : wrap.matches(kind)
        }
    }

    /// 형광펜. 누를 때마다 노랑, 회색, 로즈, 블루로 넘어가고 그다음에는 지운다.
    /// 형광펜 구간의 일부만 골랐으면 그 부분만 바꾼다.
    static func cycleHighlight(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard let line = inlineLine(doc, selection), let selected = visibleSelection(selection, in: line) else { return nil }
        for span in line.markedSpans.reversed() where contains(span.contentRange, selected) {
            guard case .highlight(let number) = span.kind else { continue }
            if number >= 4 { return resplit(doc, line, span, selected, open: "", close: "") }
            return resplit(doc, line, span, selected, open: "==", close: highlightClose(number + 1))
        }
        return wrapping(doc, line, selected, open: "==", close: "==") { kind in
            if case .highlight = kind { true } else { false }
        }
    }

    static func highlightClose(_ number: Int) -> String {
        number <= 1 ? "==" : "=={\(number)}"
    }

    /// 선택이 한 줄 안에 있고 그 줄이 코드가 아닐 때만 그 줄.
    static func inlineLine(_ doc: MarkdownDocument, _ selection: NSRange) -> MarkdownLine? {
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        guard doc.lineIndex(at: NSMaxRange(selection)) == index, !line.kind.isCode,
              selection.location >= line.contentStart else { return nil }
        return line
    }

    /// 선택의 양 끝을 보이는 글자에 붙인다. 보이는 글자가 없으면 `nil`.
    static func visibleSelection(_ selection: NSRange, in line: MarkdownLine) -> NSRange? {
        guard selection.length > 0 else { return nil }
        let start = line.visualEnd(from: selection.location)
        let end = line.visualStart(from: NSMaxRange(selection))
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    /// 다른 구간의 기호와 엇갈리지 않도록 범위를 넓힌다: 글자가 모두 든 구간은 기호까지 넣고,
    /// 한쪽만 걸친 구간은 통째로 넣는다. 범위를 통째로 안에 둔 구간은 그대로 둔다.
    static func balanced(_ range: NSRange, in line: MarkdownLine, ignoring ignored: InlineSpan? = nil) -> NSRange {
        var result = range
        var changed = true
        while changed {
            changed = false
            for span in line.markedSpans where span != ignored {
                guard NSIntersectionRange(span.range, result).length > 0,
                      !contains(result, span.range), !contains(span.contentRange, result) else { continue }
                result = NSUnionRange(result, span.range)
                changed = true
            }
        }
        return result
    }

    /// 인라인 코드 안의 글자는 서식을 받지 않는다. 코드 구간의 글자를 모두 골랐으면 구간 바깥에서
    /// 감싸도록 기호까지 넓히고, 일부만 골랐으면 `nil`.
    static func outsideCode(_ selected: NSRange, in line: MarkdownLine, allowsInside: Bool) -> NSRange? {
        var result = selected
        for span in line.markedSpans where span.kind == .code {
            guard NSIntersectionRange(span.range, result).length > 0, !contains(result, span.range) else { continue }
            if result == span.contentRange {
                result = span.range
            } else if !allowsInside {
                return nil
            }
        }
        return result
    }

    /// 구간 `span` 안의 `selected` 부분만 다른 서식(`open`…`close`, 비우면 서식 없음)으로 바꾼다.
    /// 남는 앞뒤는 원래 기호로 다시 감싼다.
    private static func resplit(
        _ doc: MarkdownDocument,
        _ line: MarkdownLine,
        _ span: InlineSpan,
        _ selected: NSRange,
        open: String,
        close: String
    ) -> TextEdit {
        let content = span.contentRange
        // 안쪽의 다른 구간과 엇갈리면 그 구간까지 넣는다. 그래도 밖으로 나가면 구간 전체를 바꾼다.
        var middle = content
        if span.kind == .code {
            middle = selected
        } else if let outside = outsideCode(selected, in: line, allowsInside: false) {
            middle = balanced(outside, in: line, ignoring: span)
        }
        // 고른 부분이 안쪽의 다른 구간 속에 있으면 그 구간째로 떼어 낸다(바깥 기호가 안쪽 구간을 가르지 않게).
        var changed = true
        while changed {
            changed = false
            for inner in line.markedSpans where inner != span && contains(content, inner.range) {
                guard NSIntersectionRange(inner.range, middle).length > 0, !contains(middle, inner.range) else { continue }
                middle = NSUnionRange(middle, inner.range)
                changed = true
            }
        }
        if !contains(content, middle) { middle = content }
        let spanOpen = doc.string(in: span.openMarker)
        let spanClose = doc.string(in: span.closeMarker)
        let left = doc.string(in: NSRange(location: content.location, length: middle.location - content.location))
        let right = doc.string(in: NSRange(location: NSMaxRange(middle), length: NSMaxRange(content) - NSMaxRange(middle)))
        let head = (left.isEmpty ? "" : spanOpen + left + spanClose) + open
        let body = doc.string(in: middle)
        let tail = close + (right.isEmpty ? "" : spanOpen + right + spanClose)
        return TextEdit(
            range: span.range,
            replacement: head + body + tail,
            selection: NSRange(location: span.range.location + head.utf16.count, length: body.utf16.count)
        )
    }

    /// 선택을 `open`…`close`로 감싼다. 선택에 든 같은 서식의 기호는 벗겨 하나로 합친다.
    private static func wrapping(
        _ doc: MarkdownDocument,
        _ line: MarkdownLine,
        _ selected: NSRange,
        open: String,
        close: String,
        strips: (InlineSpan.Kind) -> Bool
    ) -> TextEdit? {
        let isCode = open == Wrap.code.marker
        guard let selected = outsideCode(selected, in: line, allowsInside: false) else { return nil }
        let range = balanced(selected, in: line)
        let inner = line.markedSpans.filter { contains(range, $0.range) }
        // 코드로 감싸면 안의 기호가 글자로 드러나므로 벗긴다. 링크는 주소를 잃게 되므로 감싸지 않는다.
        if isCode, inner.contains(where: { if case .link = $0.kind { true } else { false } }) { return nil }
        var removed: [NSRange] = []
        for span in inner where strips(span.kind) {
            removed.append(span.openMarker)
            removed.append(span.closeMarker)
        }
        var body = ""
        var position = range.location
        for marker in removed.sorted(by: { $0.location < $1.location }) where marker.length > 0 {
            body += doc.string(in: NSRange(location: position, length: marker.location - position))
            position = NSMaxRange(marker)
        }
        body += doc.string(in: NSRange(location: position, length: NSMaxRange(range) - position))
        return TextEdit(
            range: range,
            replacement: open + body + close,
            selection: NSRange(location: range.location + open.utf16.count, length: body.utf16.count)
        )
    }
}
