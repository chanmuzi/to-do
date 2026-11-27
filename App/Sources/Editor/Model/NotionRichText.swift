import Foundation

/// Notion의 [글자, 주석 배열] 구간과 Float 원문 사이의 변환.
nonisolated enum NotionRichText {
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\w_])_(?![\s_])([^_\n]*?[^\s_])_(?![\w_])|(?<!\*)\*(?![\s*])([^*\n]*?[^\s*])\*(?!\*)"#)

    static func title(_ document: MarkdownDocument, line: MarkdownLine) -> [[Any]] {
        var result: [[Any]] = []
        var spans = line.spans[...]
        func append(_ text: String, marks: [[String]]) {
            guard !text.isEmpty else { return }
            result.append(marks.isEmpty ? [text] : [text, marks])
        }
        // 기울임은 Float에 전용 서식이 없어 교환할 때 Markdown 기호로 보존한다.
        func plain(_ range: NSRange, marks: [[String]]) {
            let text = document.string(in: range)
            let ns = text as NSString
            var start = 0
            for match in italic.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range
                append(ns.substring(with: NSRange(location: start, length: range.location - start)), marks: marks)
                append(ns.substring(with: NSRange(location: range.location + 1, length: range.length - 2)), marks: marks + [["i"]])
                start = NSMaxRange(range)
            }
            append(ns.substring(from: start), marks: marks)
        }
        func visit(_ range: NSRange, marks: [[String]]) {
            var cursor = range.location
            let end = NSMaxRange(range)
            while let span = spans.first, span.range.location < end, NSMaxRange(span.range) <= end {
                spans = spans.dropFirst()
                plain(NSRange(location: cursor, length: span.range.location - cursor), marks: marks)
                let mark: [String]?
                switch span.kind {
                case .bold: mark = ["b"]
                case .strike: mark = ["s"]
                case .underline: mark = ["_"]
                case .highlight(let id): mark = InkColor.byID[id].map { ["h", NotionHTMLFormat.colorName($0)] }
                case .link(let address): mark = LinkPolicy.openableURL(address).map { ["a", $0.absoluteString] }
                case .escape: mark = nil
                case .code: mark = ["c"]
                }
                let nested = mark.map { marks + [$0] } ?? marks
                if span.kind == .code || span.kind == .escape || span.contentRange == span.range {
                    append(document.string(in: span.contentRange), marks: nested)
                } else {
                    visit(span.contentRange, marks: nested)
                }
                cursor = NSMaxRange(span.range)
            }
            plain(NSRange(location: cursor, length: end - cursor), marks: marks)
        }
        visit(line.contentRange, marks: [])
        return result
    }

    private struct Marker: Equatable {
        let rank: Int
        let open: String
        let close: String

        init?(_ mark: [String]) {
            switch mark.first {
            case "a":
                guard mark.count >= 2 else { return nil }
                let address = mark[1].hasPrefix("/") ? "https://www.notion.so" + mark[1] : mark[1]
                guard let url = LinkPolicy.openableURL(address),
                      !url.absoluteString.contains(")") else { return nil }
                (rank, open, close) = (0, "[", "](" + url.absoluteString + ")")
            case "h":
                guard mark.count >= 2, let ink = NotionHTMLFormat.colors[mark[1]] else { return nil }
                (rank, open, close) = (1, "==", "=={" + ink.suffix + "}")
            case "b": (rank, open, close) = (2, "**", "**")
            case "s": (rank, open, close) = (3, "~~", "~~")
            case "_": (rank, open, close) = (4, "<u>", "</u>")
            case "i": (rank, open, close) = (5, "_", "_")
            case "c": (rank, open, close) = (6, "`", "`")
            default: return nil
            }
        }
    }

    static func source(_ title: [[Any]], literal: Bool = false) -> String? {
        var output = ""
        var active: [Marker] = []
        func transition(to markers: [Marker]) {
            let common = zip(active, markers).prefix(while: { $0 == $1 }).count
            for marker in active[common...].reversed() { output += marker.close }
            for marker in markers[common...] { output += marker.open }
            active = markers
        }
        var spaces = ""
        var spaceStyles: [Marker] = []
        func buffer(_ whitespace: Substring, styles: [Marker]) {
            guard !whitespace.isEmpty else { return }
            if spaces.isEmpty {
                spaceStyles = styles
            } else {
                spaceStyles = Array(spaceStyles.prefix(zip(spaceStyles, styles).prefix(while: { $0 == $1 }).count))
            }
            spaces += whitespace
        }
        func flush(before next: [Marker]) {
            guard !spaces.isEmpty else { return }
            let common = min(zip(active, spaceStyles).prefix(while: { $0 == $1 }).count,
                             zip(active, next).prefix(while: { $0 == $1 }).count)
            transition(to: Array(active.prefix(common)))
            output += spaces
            spaces = ""
        }
        for run in title {
            guard let text = run.first as? String else { return nil }
            let textValue = LineEndings.normalized(text)
            if literal { output += textValue; continue }
            let annotations = run.count > 1 ? run[1] as? [Any] : []
            guard let annotations else { return nil }
            var markers: [Marker] = []
            for case let annotation as [String] in annotations {
                if let marker = Marker(annotation), !markers.contains(where: { $0.rank == marker.rank }) {
                    markers.append(marker)
                }
            }
            markers.sort { $0.rank < $1.rank }
            for (index, part) in textValue.components(separatedBy: "\n").enumerated() {
                if index > 0 { flush(before: []); transition(to: []); output += "\n" }
                guard !part.isEmpty else { continue }
                let code = markers.last?.open == "`" && !part.contains("`")
                let styles = markers.filter { $0.open != "`" || code }
                // Float의 기호는 공백으로 열거나 닫을 수 없다.
                let leading = part.prefix(while: \.isWhitespace)
                buffer(leading, styles: styles)
                let rest = part.dropFirst(leading.count)
                let trailing = rest.reversed().prefix(while: \.isWhitespace).count
                let core = rest.dropLast(trailing)
                if !core.isEmpty {
                    flush(before: styles)
                    transition(to: styles)
                    for char in core {
                        if !code, char != "-", InlineParser.escapableCharacters.contains(char) { output.append("\\") }
                        output.append(char)
                    }
                }
                buffer(rest.suffix(trailing), styles: styles)
            }
        }
        flush(before: [])
        transition(to: [])
        return output
    }
}
