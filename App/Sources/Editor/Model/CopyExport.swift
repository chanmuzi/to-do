import Foundation

/// 복사할 때 다른 앱이 읽을 수 있는 꼴로 바꾼다(D-009).
/// 원문 조각 하나에서 표준 Markdown 글자와 HTML을 만든다.
nonisolated struct CopyExport: Sendable {
    /// 복사할 원문 조각(앱 안에서 붙여 넣을 때는 이것을 그대로 쓴다).
    let source: String
    private let doc: MarkdownDocument
    private let lines: [MarkdownLine]
    private let startsInCode: Bool

    /// - Parameter selection: 선택. 줄 머리의 감춘 기호 바로 뒤에서 시작하면 그 기호까지 넣는다.
    init(_ document: MarkdownDocument, selection: NSRange) {
        let first = document.lines[document.lineIndex(at: selection.location)]
        var start = selection.location
        if start <= (first.kind.isCode ? first.caretStart : first.contentStart) { start = first.start }
        let source = document.string(in: NSRange(location: start, length: NSMaxRange(selection) - start))
        self.init(source: source, startsInCode: first.kind == .code || first.kind == .fenceClose)
    }

    /// - Parameter startsInCode: 조각이 코드 블록 안에서 시작하는지. 그러면 첫머리를 코드로 읽는다.
    init(source: String, startsInCode: Bool = false) {
        self.source = source
        self.startsInCode = startsInCode
        if startsInCode {
            doc = MarkdownDocument("```\n" + source)
            lines = Array(doc.lines.dropFirst())
        } else {
            doc = MarkdownDocument(source)
            lines = doc.lines
        }
    }

    // MARK: 표준 Markdown

    /// 토글은 하위 항목을 가진 글머리표로, 투두는 `- [ ]`로, 형광펜은 색 번호 없이 `==글자==`로.
    var markdown: String {
        let base = baseLevel
        return lines.compactMap { line -> String? in
            let indent = String(repeating: "    ", count: max(0, line.level - base))
            switch line.kind {
            case .fenceClose where startsInCode && line.codeBlock?.lowerBound == 0:
                // 코드 블록 가운데부터 복사했으면 여는 줄이 없으므로 닫는 줄도 내보내지 않는다.
                return nil
            case .fenceOpen, .fenceClose, .code:
                return indent + doc.string(in: NSRange(location: line.start + line.indentLength, length: line.end - line.start - line.indentLength))
            case .paragraph:
                return line.contentRange.length == 0 ? "" : indent + inlineMarkdown(line)
            case .heading(let level):
                return indent + String(repeating: "#", count: level) + " " + inlineMarkdown(line)
            case .todo(let done):
                return indent + (done ? "- [x] " : "- [ ] ") + inlineMarkdown(line)
            case .bullet, .toggle:
                return indent + "- " + inlineMarkdown(line)
            }
        }.joined(separator: "\n")
    }

    /// 조각 안에서 가장 얕은 단계. 내보낼 때 이 단계를 맨 앞 칸으로 삼는다.
    private var baseLevel: Int {
        lines.filter { $0.range.length > 0 }.map(\.level).min() ?? 0
    }

    private func inlineMarkdown(_ line: MarkdownLine) -> String {
        var units = Array(doc.units[line.contentStart..<line.end])
        // 형광펜의 색 번호 `{n}`을 뒤에서부터 지운다.
        let suffixes = line.spans.compactMap { span -> Int? in
            guard case .highlight = span.kind, span.closeMarker.length > 2 else { return nil }
            return NSMaxRange(span.range) - 3 - line.contentStart
        }
        for offset in suffixes.sorted(by: >) {
            units.removeSubrange(offset..<(offset + 3))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    // MARK: HTML

    /// - Parameter highlightColors: 형광펜 번호(1...4)의 바탕색(CSS 표기).
    func html(highlightColors: [Int: String]) -> String {
        "<meta charset=\"utf-8\">" + blocks((doc.lines.count - lines.count)..<doc.lines.count, highlightColors)
    }

    private func blocks(_ range: Range<Int>, _ colors: [Int: String]) -> String {
        var out = ""
        var index = range.lowerBound
        while index < range.upperBound {
            let line = doc.lines[index]
            switch line.kind {
            case .fenceOpen, .code, .fenceClose:
                let block = line.codeBlock ?? index...index
                let last = min(block.upperBound, range.upperBound - 1)
                let code = (index...last)
                    .filter { doc.lines[$0].kind == .code }
                    .map { doc.string(in: NSRange(location: doc.lines[$0].start + doc.lines[$0].indentLength, length: doc.lines[$0].end - doc.lines[$0].start - doc.lines[$0].indentLength)) }
                    .joined(separator: "\n")
                out += "<pre><code>" + Self.escape(code) + "</code></pre>"
                index = last + 1
            case .todo, .bullet, .toggle:
                out += "<ul>"
                while index < range.upperBound, doc.lines[index].kind.isListItem, doc.lines[index].level == line.level {
                    let item = doc.lines[index]
                    let end = min(item.subtreeEnd, range.upperBound)
                    out += "<li>"
                    if case .todo(let done) = item.kind {
                        out += "<input type=\"checkbox\" disabled\(done ? " checked" : "")> "
                    }
                    out += inline(item.contentRange, item.spans, colors)
                    if index + 1 < end { out += blocks((index + 1)..<end, colors) }
                    out += "</li>"
                    index = end
                }
                out += "</ul>"
            case .heading(let level):
                out += "<h\(level)>" + inline(line.contentRange, line.spans, colors) + "</h\(level)>"
                index += 1
            case .paragraph:
                if line.contentRange.length > 0 {
                    out += "<p>" + inline(line.contentRange, line.spans, colors) + "</p>"
                }
                index += 1
            }
        }
        return out
    }

    private func inline(_ range: NSRange, _ spans: [InlineSpan], _ colors: [Int: String]) -> String {
        var out = ""
        var position = range.location
        for span in spans where span.range.location >= position && NSMaxRange(span.range) <= NSMaxRange(range) {
            guard span.range.location >= position else { continue }
            out += Self.escape(doc.string(in: NSRange(location: position, length: span.range.location - position)))
            let inner = spans.filter {
                $0.range != span.range
                    && $0.range.location >= span.contentRange.location
                    && NSMaxRange($0.range) <= NSMaxRange(span.contentRange)
            }
            let body = span.kind == .code
                ? Self.escape(doc.string(in: span.contentRange))
                : inline(span.contentRange, inner, colors)
            switch span.kind {
            case .bold: out += "<strong>\(body)</strong>"
            case .strike: out += "<s>\(body)</s>"
            case .code: out += "<code>\(body)</code>"
            case .highlight(let number):
                let color = colors[number].map { " style=\"background-color:\($0)\"" } ?? ""
                out += "<mark\(color)>\(body)</mark>"
            case .link(let url):
                out += "<a href=\"\(Self.escape(url))\">\(body)</a>"
            }
            position = NSMaxRange(span.range)
        }
        out += Self.escape(doc.string(in: NSRange(location: position, length: NSMaxRange(range) - position)))
        return out
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
