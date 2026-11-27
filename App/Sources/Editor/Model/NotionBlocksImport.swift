import Foundation

nonisolated enum NotionBlocksImport {
    static func source(from data: Data) -> String? {
        guard let json = ChromiumCustomData.decode(data)?[ChromiumCustomData.notionBlocks] else { return nil }
        return source(json)
    }

    static func source(_ json: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let roots = object["blocks"] as? [[String: Any]] else { return nil }
        var lines: [String] = []
        for root in roots {
            guard let id = root["blockId"] as? String, let tree = root["blockSubtree"] as? [String: Any],
                  tree["__version__"] as? Int == 3, let records = tree["block"] as? [String: Any] else { return nil }
            var pending = [(id, 0)]
            var seen: Set<String> = []
            while let (id, depth) = pending.popLast() {
                guard seen.insert(id).inserted, depth <= MarkdownDocument.maxLevel,
                      let record = records[id] as? [String: Any], let block = record["value"] as? [String: Any],
                      block["id"] as? String == id, let type = block["type"] as? String else { return nil }
                guard let properties = (block["properties"] ?? [:]) as? [String: Any],
                      let title = (properties["title"] ?? []) as? [[Any]],
                      let format = (block["format"] ?? [:]) as? [String: Any],
                      let children = (block["content"] ?? []) as? [String] else { return nil }
                let indent = String(repeating: "\t", count: depth)
                var childDepth = depth + 1
                if type == "code" {
                    guard let code = NotionRichText.source(title, literal: true) else { return nil }
                    let language = (properties["language"] as? [[String]])?.first?.first ?? ""
                    let name = NotionCodeLanguage.name(language)
                    let body = code.components(separatedBy: "\n")
                    guard !body.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "```" }) else { return nil }
                    lines.append(indent + "```" + (name == "Plain Text" ? "" : name.lowercased()))
                    lines += body.map { indent + $0 }
                    lines.append(indent + "```")
                } else {
                    let marker: String
                    let known: Bool
                    switch type {
                    case "text": (marker, known) = ("", true)
                    case "header", "sub_header", "sub_sub_header":
                        let prefix = format["toggleable"] as? Bool == true ? "+ " : ""
                        let level = type == "header" ? 1 : type == "sub_header" ? 2 : 3
                        (marker, known) = (prefix + String(repeating: "#", count: level) + " ", true)
                    case "to_do":
                        let checked = (properties["checked"] as? [[String]])?.first?.first == "Yes"
                        (marker, known) = (checked ? "[x] " : "[ ] ", true)
                    case "toggle": (marker, known) = ("+ ", true)
                    case "bulleted_list": (marker, known) = ("- ", true)
                    case "quote": (marker, known) = ("> ", true)
                    case "divider": (marker, known) = ("---", true)
                    default: (marker, known) = ("", false)
                    }
                    let runs = known ? title : title.map { Array($0.prefix(1)) }
                    guard let text = NotionRichText.source(runs) else { return nil }
                    if known || !text.isEmpty {
                        let ink = known ? (format["block_color"] as? String).flatMap { NotionHTMLFormat.colors[$0] } : nil
                        let body = text.replacingOccurrences(of: "\n", with: "\\\n" + indent)
                        lines.append(indent + marker + (type == "divider" ? "" : body + (ink?.comment ?? "")))
                    } else {
                        childDepth = depth
                    }
                }
                pending += children.reversed().map { ($0, childDepth) }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
