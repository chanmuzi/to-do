import Foundation
import libxml2

/// HTML 조각만 읽는다. 렌더링이나 리소스 로딩 없이, 인식한 블록 전체를 Float 원문으로 바꾼다.
nonisolated enum NotionHTMLImport {
    static func source(_ html: String) -> String? {
        guard html.range(of: #"<details\b|checkbox|highlight-|block-color-|bulleted-list|numbered-list"#,
                         options: [.regularExpression, .caseInsensitive]) != nil, !html.contains("\0") else { return nil }
        // meta로 시작하는 조각에서도 HTML5 details가 암묵적인 head 안에 들어가지 않게 한다.
        let hasDocument = html.range(of: #"<(?:html|head|body)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let input = hasDocument ? html : "<body>" + html + "</body>"
        guard let length = Int32(exactly: input.utf8.count),
              let context = htmlNewParserCtxt() else { return nil }
        defer { htmlFreeParserCtxt(context) }
        let options = HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        guard let document = htmlCtxtReadMemory(context, input, length, nil, "UTF-8", Int32(options)) else { return nil }
        defer { xmlFreeDoc(document) }
        guard context.pointee.lastError.level != XML_ERR_FATAL, let root = xmlDocGetRootElement(document) else { return nil }
        var writer = Writer()
        guard (try? writer.blocks([Node(root)], depth: 0)) != nil, writer.recognized else { return nil }
        let source = writer.lines.joined(separator: "\n")
        return source.isEmpty ? nil : source
    }

    private enum ImportError: Error { case unsupported }

    /// 노드는 위 document가 살아 있는 동안에만 쓴다. libxml2가 HTML 엔티티와 생략된 닫는 태그를 처리한다.
    private struct Node {
        let ptr: xmlNodePtr
        init(_ ptr: xmlNodePtr) { self.ptr = ptr }
        var tag: String { String(cString: ptr.pointee.name) }
        var isText: Bool { ptr.pointee.type == XML_TEXT_NODE }
        var text: String { ptr.pointee.content.map { String(cString: $0) } ?? "" }
        var children: [Node] {
            var result: [Node] = []
            var child = ptr.pointee.children
            while let current = child {
                if current.pointee.type == XML_TEXT_NODE || current.pointee.type == XML_ELEMENT_NODE {
                    result.append(Node(current))
                }
                child = current.pointee.next
            }
            return result
        }
        func attribute(_ name: String) -> String? {
            guard !isText, let attr = xmlHasProp(ptr, name) else { return nil }
            return attr.pointee.children?.pointee.content.map { String(cString: $0) } ?? ""
        }
        var classes: [Substring] { (attribute("class") ?? "").split(whereSeparator: \.isWhitespace) }
        func color(_ prefix: String) -> InkColor? {
            guard let name = classes.first(where: { $0.hasPrefix(prefix) }) else { return nil }
            return NotionHTMLFormat.colors[String(name.dropFirst(prefix.count))]
        }
        var blockInk: InkColor? { color("block-color-") }
        var heading: Int? { ["h1": 1, "h2": 2, "h3": 3][tag] }
        var summaryHeading: Int? {
            if let heading = children.compactMap(\.heading).first { return heading }
            let styles = (attribute("style") ?? "").lowercased().split(separator: ";")
            for rule in styles {
                let pair = rule.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if pair.count == 2, pair[0] == "font-size" {
                    return NotionHTMLFormat.headingSizes.first { $0.value == pair[1] }?.key
                }
            }
            return nil
        }
        var checkbox: Bool? {
            if tag == "input", attribute("type")?.lowercased() == "checkbox" { return attribute("checked") != nil }
            if classes.contains("checkbox-on") { return true }
            if classes.contains("checkbox-off") { return false }
            return nil
        }
        var isInline: Bool {
            isText || ["a", "b", "strong", "i", "em", "s", "del", "strike", "u", "mark", "span", "br", "code", "label"].contains(tag)
        }
        var whitespace: Bool { isText && text.allSatisfy(\.isWhitespace) }
    }

    private struct Writer {
        var lines: [String] = []
        var recognized = false

        mutating func emit(_ marker: String, _ content: String, at depth: Int, ink: InkColor? = nil) {
            let indent = String(repeating: "\t", count: depth)
            let text = content.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\n", with: "\\\n" + indent)
            lines.append(indent + marker + text + (ink?.comment ?? ""))
            if ink != nil { recognized = true }
        }

        /// 인라인 형제는 한 문단이다. 들여쓰기용 HTML 공백만 있는 구간은 줄로 만들지 않는다.
        mutating func blocks(_ nodes: [Node], depth: Int) throws {
            if depth > MarkdownDocument.maxLevel, nodes.contains(where: { !$0.whitespace }) { throw ImportError.unsupported }
            var pending = ""
            for node in nodes {
                if node.isInline {
                    pending += try inline(node)
                    continue
                }
                if !pending.trimmingCharacters(in: .whitespaces).isEmpty { emit("", pending, at: depth) }
                pending = ""
                try block(node, depth: depth)
            }
            if !pending.trimmingCharacters(in: .whitespaces).isEmpty { emit("", pending, at: depth) }
        }

        mutating func block(_ node: Node, depth: Int) throws {
            let children = node.children
            if node.classes.contains("bulleted-list") || node.classes.contains("numbered-list") { recognized = true }
            switch node.tag {
            case "html", "body", "article", "section", "div", "header", "ul", "ol":
                try blocks(children, depth: depth)
            case "head", "style", "script", "meta", "link", "title":
                break
            case "p", "h1", "h2", "h3":
                let marker = node.heading.map { String(repeating: "#", count: $0) + " " } ?? ""
                emit(marker, try inlineContents(children), at: depth, ink: node.blockInk)
            case "details":
                let body = children.drop(while: \.whitespace)
                guard let summary = body.first, summary.tag == "summary" else { throw ImportError.unsupported }
                recognized = true
                let heading = summary.summaryHeading.map { String(repeating: "#", count: $0) + " " } ?? ""
                emit("+ " + heading, try inlineContents(summary.children), at: depth, ink: summary.blockInk ?? node.blockInk)
                try blocks(Array(body.dropFirst()), depth: depth + 1)
            case "li":
                try listItem(node, depth: depth)
            case "blockquote":
                let label = children.prefix(while: \.isInline)
                if label.contains(where: { !$0.whitespace }) {
                    emit("> ", try inlineContents(Array(label)), at: depth, ink: node.blockInk)
                    try blocks(Array(children.dropFirst(label.count)), depth: depth + 1)
                } else {
                    for child in children where !child.whitespace {
                        if child.tag == "p" {
                            emit("> ", try inlineContents(child.children), at: depth, ink: child.blockInk ?? node.blockInk)
                        } else { try blocks([child], depth: depth + 1) }
                    }
                }
            case "hr":
                emit("---", "", at: depth)
            case "pre":
                let code = children.first { $0.tag == "code" }
                let lang = code?.classes.first { $0.hasPrefix("language-") }?.dropFirst("language-".count) ?? ""
                let indent = String(repeating: "\t", count: depth)
                let body = try literal(children).components(separatedBy: "\n")
                guard !body.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "```" }) else { throw ImportError.unsupported }
                lines += [indent + "```" + lang] + body.map { indent + $0 } + [indent + "```"]
            default:
                throw ImportError.unsupported
            }
        }

        mutating func listItem(_ item: Node, depth: Int) throws {
            var body = item.children.drop(while: \.whitespace)
            if body.first?.tag == "details" {
                try blocks(Array(body), depth: depth)
                return
            }
            // <li><p><input ...> 글</p><ul>... 형태도 같은 항목이다.
            if let first = body.first, first.tag == "p" || first.tag == "label" {
                body = (first.children + body.dropFirst())[...]
            }
            body = body.drop(while: \.whitespace)
            let checkbox = body.first?.checkbox
            if checkbox != nil { body = body.dropFirst(); recognized = true }
            let label = body.prefix(while: \.isInline)
            let marker = checkbox.map { $0 ? "[x] " : "[ ] " } ?? "- "
            emit(marker, try inlineContents(Array(label)), at: depth, ink: item.blockInk ?? label.compactMap(\.blockInk).first)
            try blocks(Array(body.dropFirst(label.count)), depth: depth + 1)
        }

        func literal(_ nodes: [Node]) throws -> String {
            try nodes.map { node in
                if node.isText { return node.text }
                if node.tag == "br" { return "\n" }
                guard node.isInline else { throw ImportError.unsupported }
                return try literal(node.children)
            }.joined()
        }

        mutating func inlineContents(_ nodes: [Node], allowColor: Bool = true) throws -> String {
            try nodes.map { try inline($0, allowColor: allowColor) }.joined()
        }

        mutating func inline(_ node: Node, allowColor: Bool = true) throws -> String {
            if node.isText {
                let text = node.text.replacingOccurrences(of: "[\\t\\n\\r ]+", with: " ", options: .regularExpression)
                return text.reduce(into: "") { result, char in
                    if InlineParser.escapableCharacters.contains(char), char != "-" { result.append("\\") }
                    result.append(char)
                }
            }
            if node.tag == "br" { return "\n" }
            if node.tag == "code" {
                let text = try literal(node.children)
                return text.contains("`") ? text : "`" + text + "`"
            }
            guard node.isInline || node.heading != nil else { throw ImportError.unsupported }
            // Float는 한 글자에 색 하나를 저장한다. 겹친 mark는 바깥 색과 안쪽의 다른 서식을 살린다.
            let ink = allowColor ? node.color("highlight-") : nil
            let text = try inlineContents(node.children, allowColor: allowColor && ink == nil)
            let open: String, close: String
            switch node.tag {
            case "strong", "b": (open, close) = ("**", "**")
            case "s", "strike", "del": (open, close) = ("~~", "~~")
            case "u": (open, close) = ("<u>", "</u>")
            case "a":
                guard let href = node.attribute("href"), let url = LinkPolicy.openableURL(href),
                      !url.absoluteString.contains(")") else { return text }
                (open, close) = ("[", "](" + url.absoluteString + ")")
            default:
                guard let ink else { return text }
                recognized = true
                (open, close) = ("==", "=={" + ink.suffix + "}")
            }
            // Float의 인라인 기호는 물리 줄을 건너거나 공백으로 열고 닫을 수 없다.
            return text.components(separatedBy: "\n").map { part in
                let core = part.trimmingCharacters(in: .whitespaces)
                guard !core.isEmpty, let range = part.range(of: core) else { return part }
                return part[..<range.lowerBound] + open + core + close + part[range.upperBound...]
            }.joined(separator: "\n")
        }
    }
}
