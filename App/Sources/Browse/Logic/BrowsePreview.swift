import Foundation

/// 본문을 한 줄로 편 글(spec 8의 "본문 첫머리"). 줄 머리의 기호(들여쓰기, 투두, 글머리표, 토글 `+ `, 인용문 `> `, 제목)와
/// 인라인 기호(굵게, 취소선, 형광펜, 코드)를 떼고, 빈 줄을 건너뛰어 쉼표로 잇는다. 찾기도 이 글에서 한다.
nonisolated enum BrowsePreview {
    private static let contextLength = 8
    private static let maximumLeadingContext = 12

    static func flatten(_ body: String) -> String {
        body
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let text = stripInline(stripLineMarker(String(line)))
                return text.isEmpty ? nil : text
            }
            .joined(separator: ", ")
    }

    /// 일치한 글자 주위의 문맥을 보여 주고, 앞을 생략했으면 말줄임표까지 세어 강조 범위를 돌려준다.
    static func display(_ flattened: String, match: Range<Int>?) -> (text: String, highlight: Range<Int>?) {
        guard let match else { return ("", nil) }
        let hit = flattened.index(flattened.startIndex, offsetBy: match.lowerBound)
        let start = contextStart(in: flattened[..<hit])
        let omission = start == flattened.startIndex ? "" : "…"
        let before = omission + flattened[start..<hit]
        let text = before + flattened[hit...].prefix(match.count + contextLength)
        return (text, before.count..<(before.count + match.count))
    }

    private static func contextStart(in prefix: Substring) -> String.Index {
        let preferred = prefix.suffix(contextLength).startIndex
        guard preferred != prefix.startIndex else { return preferred }
        let earliest = prefix.suffix(maximumLeadingContext).startIndex

        func isSeparator(_ character: Character) -> Bool { character.isWhitespace || character == "," }
        func isWordStart(_ index: String.Index) -> Bool {
            !isSeparator(prefix[index]) && (index == prefix.startIndex || isSeparator(prefix[prefix.index(before: index)]))
        }

        if !isSeparator(prefix[preferred]),
           let start = prefix[earliest...preferred].indices.reversed().first(where: isWordStart) {
            return start
        }
        return prefix[preferred...].indices.first(where: isWordStart) ?? prefix.endIndex
    }

    private static let lineMarker = regex(#"^\s*(?:(?:[-*]\s+)?\[[ xX]\]\s+|[-*+]\s+|>\s*|#{1,3}\s+|```.*$)?"#)
    private static let inlineMarks = regex(#"\*\*|~~|==(?:\{[1-4]\})?|`"#)
    private static let link = regex(#"\[([^\]]+)\]\([^)\s]+\)"#)

    private static func stripLineMarker(_ line: String) -> String {
        replace(lineMarker, in: line, with: "")
    }

    private static func stripInline(_ line: String) -> String {
        replace(inlineMarks, in: replace(link, in: line, with: "$1"), with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template
        )
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("본문 기호 무늬가 잘못됐습니다: \(error)")
        }
    }
}
