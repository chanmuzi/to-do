import Foundation

/// 최상위 블록마다 자기 자손만 담은 v3 레코드 맵을 만든다.
nonisolated struct NotionBlocksExport {
    let document: MarkdownDocument

    func json(startingAt first: Int) -> String? {
        var roots: [[String: Any]] = []
        var index = first
        while index < document.lines.count {
            var records: [String: Any] = [:]
            let id = appendBlock(at: &index, before: document.lines.count, parent: nil, to: &records)
            roots.append(["blockId": id, "blockSubtree": ["__version__": 3, "block": records]])
        }
        let object: [String: Any] = ["blocks": roots, "action": "copy", "wasContiguousSelection": true]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func appendBlock(at index: inout Int, before limit: Int, parent: (id: String, level: Int)?,
                             to records: inout [String: Any]) -> String {
        let row = index
        let line = document.lines[row]
        let id = UUID().uuidString.lowercased()
        var properties: [String: Any] = [:]
        var format: [String: Any] = [:]
        let type: String
        if line.kind.isCode {
            type = "code"
            let last = min(line.codeBlock?.upperBound ?? row, limit - 1)
            let code = document.lines[row...last].filter { $0.kind == .code }.map {
                document.string(in: $0.contentRange)
            }.joined(separator: "\n")
            properties["title"] = [[code]]
            let language = line.kind == .fenceOpen ? String(document.string(in: line.contentRange).dropFirst(3)) : ""
            properties["language"] = [[NotionCodeLanguage.name(language)]]
            index = last + 1
        } else {
            let rows = document.blockLines(at: row)
            var title: [[Any]] = []
            for number in rows {
                if number > row { title.append(["\n"]) }
                title += NotionRichText.title(document, line: document.lines[number])
            }
            properties["title"] = title
            if let ink = document.blockColor(at: row) { format["block_color"] = NotionHTMLFormat.colorName(ink) }
            switch line.kind {
            case .toggle: type = "toggle"
            case .heading(let level), .toggleHeading(let level):
                type = ["header", "sub_header", "sub_sub_header"][level - 1]
                if line.kind.isToggle { format["toggleable"] = true }
            case .todo(let done):
                type = "to_do"
                properties["checked"] = [[done ? "Yes" : "No"]]
            case .bullet: type = "bulleted_list"
            case .quote: type = "quote"
            case .divider: type = "divider"
            default: type = "text"
            }
            index = rows.upperBound + 1
        }

        var value: [String: Any] = ["id": id, "type": type, "version": 1, "alive": true]
        if type != "divider" { value["properties"] = properties }
        if !format.isEmpty { value["format"] = format }
        if let parent {
            value["parent_id"] = parent.id
            value["parent_table"] = "block"
        }
        var children: [String] = []
        let end = min(limit, line.subtreeEnd)
        // 토글 안의 빈 구분 줄과 그 뒤의 자식은 형제다.
        let separator = line.isBlankParagraph && line.level <= (parent?.level ?? -1)
        while !separator && index < end {
            children.append(appendBlock(at: &index, before: end, parent: (id, line.level), to: &records))
        }
        if !children.isEmpty { value["content"] = children }
        records[id] = ["value": value]
        return id
    }
}

nonisolated enum NotionCodeLanguage {
    private static let names = """
    ABAP Arduino Bash BASIC C Clojure CoffeeScript C++ C# CSS Dart Diff Docker Elixir Elm Erlang Flow Fortran F# \
    Gherkin GLSL Go GraphQL Groovy Haskell HTML Java JavaScript JSON Julia Kotlin LaTeX Less Lisp LiveScript Lua \
    Makefile Markdown Markup MATLAB Mermaid Nix Objective-C OCaml Pascal Perl PHP PowerShell Prolog Protobuf Python \
    R Reason Ruby Rust Sass Scala Scheme SCSS Shell SQL Swift TypeScript VB.Net Verilog VHDL WebAssembly XML YAML
    """.split(separator: " ").map(String.init) + ["Visual Basic", "Java/C/C++/C#"]

    static func name(_ source: String) -> String {
        let key = source.trimmingCharacters(in: .whitespaces).lowercased()
        let aliases = ["js": "JavaScript", "ts": "TypeScript", "py": "Python", "sh": "Shell",
                       "yml": "YAML", "rs": "Rust", "cpp": "C++", "cs": "C#", "vb": "Visual Basic"]
        return aliases[key] ?? names.first { $0.lowercased() == key } ?? "Plain Text"
    }
}
