import Foundation

/// 복사할 때 다른 앱이 읽을 수 있는 꼴로 바꾼다(D-009).
/// 원문 조각 하나에서 표준 Markdown 글자와 HTML을 만든다.
nonisolated struct CopyExport: Sendable {
    /// 복사할 원문 조각(앱 안에서 붙여 넣을 때는 이것을 그대로 쓴다).
    let source: String
    private let doc: MarkdownDocument
    private let lines: [MarkdownLine]
    private let startsInCode: Bool

    /// - Parameter selection: 선택.
    ///   - 첫 줄의 감춘 줄 머리(들여쓰기, 목록 기호)는 선택이 그 줄 끝을 넘어갈 때만 넣는다.
    ///     한 줄 안의 글자만 골랐으면 기호 없이 그 글자만 나간다.
    ///   - 마지막 줄에서 고른 것이 줄 머리뿐이면(⇧↓로 아랫줄 글자 시작까지 고른 경우) 그 줄은 뺀다.
    init(_ document: MarkdownDocument, selection: NSRange) {
        let firstIndex = document.lineIndex(at: selection.location)
        let first = document.lines[firstIndex]
        var start = selection.location
        var end = NSMaxRange(selection)
        let firstHead = Self.hiddenHeadEnd(of: first)
        if start <= firstHead, first.kind != .divider {
            start = end > first.end ? first.start : min(firstHead, end)
        }
        let lastIndex = document.lineIndex(at: end)
        if lastIndex > firstIndex {
            let last = document.lines[lastIndex]
            let lastHead = Self.hiddenHeadEnd(of: last)
            if end > last.start, end <= lastHead, lastHead < last.end {
                end = document.lines[lastIndex - 1].end
            }
        }
        let fragment = Self.balanced(document, start: start, end: max(start, end))
        self.init(source: fragment, startsInCode: first.kind == .code || first.kind == .fenceClose)
    }

    /// 고른 범위의 원문에, 잘려 나간 인라인 기호를 채운 것. 기호는 화면에 보이지 않아 고를 수 없으므로,
    /// 서식 구간의 글자만 골라도 그 서식이 함께 나가게 한다: 구간의 글자 맨 앞이나 맨 끝에 닿은 쪽은
    /// 기호까지 넣고, 구간 한가운데에서 잘린 쪽은 기호를 덧붙인다.
    private static func balanced(_ document: MarkdownDocument, start: Int, end: Int) -> String {
        guard end > start else { return "" }
        var lower = start
        var upper = end
        var opens = ""
        var closes = ""
        let first = document.line(at: start)
        if !first.kind.isCode {
            let spans = first.hiddenSpans.sorted { $0.range.length < $1.range.length }
            // 글자 맨 앞에 닿은 구간은 여는 기호까지 넣는다. 안쪽 구간부터.
            for span in spans where lower == span.contentRange.location && end > lower {
                lower = span.range.location
            }
            // 한가운데에서 잘린 구간은 여는 기호를 덧붙인다. 바깥 구간부터.
            for span in spans.reversed() where span.contentRange.location < start && start < NSMaxRange(span.contentRange) {
                opens += document.string(in: span.openMarker)
            }
        }
        let last = document.line(at: end)
        if !last.kind.isCode {
            let spans = last.hiddenSpans.sorted { $0.range.length < $1.range.length }
            for span in spans where upper == NSMaxRange(span.contentRange) && start < upper {
                upper = NSMaxRange(span.range)
            }
            for span in spans where span.contentRange.location < end && end < NSMaxRange(span.contentRange) {
                closes += document.string(in: span.closeMarker)
            }
        }
        return opens + document.string(in: NSRange(location: lower, length: upper - lower)) + closes
    }

    /// 화면에서 글자로 보이지 않는 줄 머리의 끝.
    private static func hiddenHeadEnd(of line: MarkdownLine) -> Int {
        line.kind.isCode ? line.caretStart : line.contentStart
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

    /// 토글은 하위 항목을 가진 글머리표로, 투두는 `- [ ]`로, 인용문은 `> `로, 색과 밑줄은 보이는 글자로 내보낸다.
    var markdown: String {
        let base = baseLevel
        func usesInlineBreaks(_ row: Int) -> Bool {
            let rows = doc.blockLines(at: row)
            guard rows.count > 1 else { return false }
            if doc.lines[rows.lowerBound].kind.headingLevel != nil { return true }
            return rows.contains { i in
                let line = doc.lines[i]
                guard line.contentRange.length > 0 else { return true }
                guard line.continuationOf != nil else { return false }
                let text = doc.string(in: line.contentRange).trimmingCharacters(in: .whitespaces)
                guard let first = text.first else { return true }
                // CommonMark의 목록, 인용문, 제목, 코드와 HTML 블록이 문단을 끊을 수 있다.
                return first.isNumber || "#>+-*_`~=<".contains(first)
            }
        }
        var inlineBreaks = false
        return lines.compactMap { line -> String? in
            let row = doc.lineIndex(at: line.start)
            if line.continuationOf == nil { inlineBreaks = usesInlineBreaks(row) }
            if inlineBreaks && line.continuationOf != nil { return nil }
            let content = inlineBreaks ? doc.blockLines(at: row).map { inlineMarkdown(doc.lines[$0], keepingBreak: false) }.joined(separator: "<br>") : inlineMarkdown(line)
            let indent = String(repeating: "\t", count: max(0, line.level - base))
            if let owner = line.continuationOf {
                let kind = doc.lines[owner].kind
                let prefix = kind == .quote ? "> " : kind.isListItem ? "  " : ""
                return indent + prefix + content
            }
            switch line.kind {
            case .fenceClose where startsInCode && line.codeBlock?.lowerBound == 0:
                // 코드 블록 가운데부터 복사했으면 여는 줄이 없으므로 닫는 줄도 내보내지 않는다.
                return nil
            case .fenceOpen, .fenceClose, .code:
                return indent + doc.string(in: NSRange(location: line.start + line.indentLength, length: line.end - line.start - line.indentLength))
            case .divider:
                let needsBlank = row > doc.lines.count - lines.count && doc.lines[row - 1].contentRange.length > 0
                return (needsBlank ? "\n" : "") + indent + "---"
            case .paragraph:
                return content.isEmpty ? "" : indent + content
            case .heading(let level):
                return indent + String(repeating: "#", count: level) + " " + content
            case .todo(let done):
                return indent + (done ? "- [x] " : "- [ ] ") + content
            case .toggleHeading(let level):
                return indent + "- " + String(repeating: "#", count: level) + " " + content
            case .bullet, .toggle:
                return indent + "- " + content
            case .quote:
                return indent + "> " + content
            }
        }.joined(separator: "\n")
    }

    /// 조각 안에서 가장 얕은 단계. 내보낼 때 이 단계를 맨 앞 칸으로 삼는다.
    private var baseLevel: Int {
        lines.filter { $0.range.length > 0 }.map(\.level).min() ?? 0
    }

    private func inlineMarkdown(_ line: MarkdownLine, keepingBreak: Bool = true) -> String {
        let end = keepingBreak ? line.inkComment?.location ?? line.end : line.contentEnd
        var units = Array(doc.units[line.contentStart..<end])
        let markers = line.spans.filter {
            switch $0.kind { case .highlight, .underline: true; default: false }
        }.flatMap { [$0.openMarker, $0.closeMarker] }
        for marker in markers.sorted(by: { $0.location > $1.location }) {
            units.removeSubrange((marker.location - line.contentStart)..<(NSMaxRange(marker) - line.contentStart))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    var notionBlocksJSON: String? {
        NotionBlocksExport(document: doc).json(startingAt: doc.lines.count - lines.count)
    }

    var chromiumData: Data? {
        notionBlocksJSON.flatMap { ChromiumCustomData.encode([ChromiumCustomData.notionBlocks: $0]) }
    }

    // MARK: HTML

    /// - Parameter highlightColors: 글자색과 바탕색 식별자별 라이트 CSS 값.
    func html(highlightColors: [Int: String]) -> String {
        "<meta charset=\"utf-8\">" + blocks((doc.lines.count - lines.count)..<doc.lines.count, highlightColors)
    }

    private func inkAttributes(_ ink: InkColor?, _ colors: [Int: String], inline: Bool = false,
                               classes: [String] = [], styles: [String] = []) -> String {
        var classes = classes
        var styles = styles
        if let ink {
            classes.append((inline ? "highlight-" : "block-color-") + NotionHTMLFormat.colorName(ink))
            if inline && ink.foreground { styles.append("background-color:transparent") }
            if let css = colors[ink.id] { styles.append((ink.foreground ? "color:" : "background-color:") + css) }
        }
        let classAttr = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        let styleAttr = styles.isEmpty ? "" : " style=\"\(styles.joined(separator: ";"))\""
        return classAttr + styleAttr
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
                let language = line.kind == .fenceOpen
                    ? doc.string(in: line.contentRange).dropFirst(3).split(whereSeparator: \.isWhitespace).first : nil
                let attribute = language.map { " class=\"language-\(Self.escape(String($0)))\"" } ?? ""
                out += "<pre><code\(attribute)>" + Self.escape(code) + "</code></pre>"
                index = last + 1
            case .bullet:
                out += "<ul>"
                while index < range.upperBound, doc.lines[index].kind == .bullet, doc.lines[index].level == line.level {
                    let end = min(doc.lines[index].subtreeEnd, range.upperBound)
                    let children = doc.blockLines(at: index).upperBound + 1
                    let attrs = inkAttributes(doc.blockColor(at: index), colors)
                    let content = blockContent(at: index, colors)
                    let title = attrs.isEmpty ? content : "<span\(attrs)>\(content)</span>"
                    out += "<li>" + title + blocks(children..<end, colors) + "</li>"
                    index = end
                }
                out += "</ul>"
            case .todo, .toggle, .toggleHeading:
                let end = min(line.subtreeEnd, range.upperBound)
                let childrenStart = doc.blockLines(at: index).upperBound + 1
                let children = blocks(childrenStart..<end, colors)
                let content = blockContent(at: index, colors)
                let ink = doc.blockColor(at: index)
                if line.kind == .toggle {
                    out += "<ul class=\"toggle\"><li><details open=\"\"><summary\(inkAttributes(ink, colors))>\(content)</summary>"
                        + children + "</details></li></ul>"
                } else if case .toggleHeading(let level) = line.kind {
                    let size = NotionHTMLFormat.headingSizes[level] ?? "1em"
                    let summary = inkAttributes(ink, colors, styles: ["font-weight:600", "font-size:\(size)", "line-height:1.3", "margin:0"])
                    out += "<details open=\"\"><summary\(summary)>" + content
                        + "</summary><div class=\"indented\">" + children + "</div></details>"
                } else if case .todo(let done) = line.kind {
                    let checkbox = done ? "checkbox-on" : "checkbox-off"
                    let state = done ? "checked" : "unchecked"
                    let label = inkAttributes(ink, colors, classes: ["to-do-children-\(state)"])
                    out += "<ul class=\"to-do-list\"><li><input type=\"checkbox\" class=\"checkbox \(checkbox)\" disabled"
                        + (done ? " checked" : "") + "> <span\(label)>"
                        + content + "</span>"
                        + children + "</li></ul>"
                }
                index = end
            case .quote:
                // 같은 단계에 이어지는 인용문 줄은 하나의 인용문이다. 줄마다 문단이고, 하위 줄은 그 안에 든다.
                out += "<blockquote>"
                while index < range.upperBound, doc.lines[index].kind == .quote, doc.lines[index].level == line.level {
                    let item = doc.lines[index]
                    let end = min(item.subtreeEnd, range.upperBound)
                    out += "<p\(inkAttributes(doc.blockColor(at: index), colors))>" + blockContent(at: index, colors) + "</p>"
                    let children = doc.blockLines(at: index).upperBound + 1
                    if children < end { out += blocks(children..<end, colors) }
                    index = end
                }
                out += "</blockquote>"
            case .heading(let level):
                out += "<h\(level)\(inkAttributes(doc.blockColor(at: index), colors))>" + blockContent(at: index, colors) + "</h\(level)>"
                index = doc.blockLines(at: index).upperBound + 1
            case .divider:
                out += "<hr>"
                index += 1
            case .paragraph:
                if line.contentRange.length > 0 || line.hasHardBreak {
                    out += "<p\(inkAttributes(doc.blockColor(at: index), colors))>" + blockContent(at: index, colors) + "</p>"
                }
                index = doc.blockLines(at: index).upperBound + 1
            }
        }
        return out
    }

    private func blockContent(at index: Int, _ colors: [Int: String]) -> String {
        doc.blockLines(at: index).map { inline(doc.lines[$0].contentRange, doc.lines[$0].spans, colors) }.joined(separator: "<br>")
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
                out += "<mark\(inkAttributes(InkColor.byID[number], colors, inline: true))>\(body)</mark>"
            case .underline: out += "<u>\(body)</u>"
            case .link(let url):
                // 웹 주소와 메일 주소만 링크로 내보낸다. 나머지는 글자만 남긴다.
                if let target = LinkPolicy.openableURL(url) {
                    out += "<a href=\"\(Self.escape(target.absoluteString))\">\(body)</a>"
                } else {
                    out += body
                }
            case .escape:
                // 백슬래시는 내보내지 않는다. 막은 글자만 남는다.
                out += body
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
