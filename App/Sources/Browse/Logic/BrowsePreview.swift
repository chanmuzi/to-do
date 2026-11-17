import Foundation

/// 본문을 한 줄로 편 글(spec 8의 "본문 첫머리"). 줄 머리의 기호(들여쓰기, 투두, 글머리표, 토글 `+ `, 인용문 `> `, 제목)와
/// 인라인 기호(굵게, 취소선, 형광펜, 코드)를 떼고, 빈 줄을 건너뛰어 쉼표로 잇는다. 찾기도 이 글에서 한다.
nonisolated enum BrowsePreview {
    /// 한 줄로 펼 때 읽는 본문의 길이 한도(글자). 아주 긴 노트의 뒤쪽은 노트 찾기에서 찾지 않는다.
    static let scanLimit = 20000
    /// 줄에 보일 글의 길이 한도. 넘는 것은 어차피 잘려 보인다.
    static let displayLimit = 160

    static func flatten(_ body: String) -> String {
        body.prefix(scanLimit)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let text = stripInline(stripLineMarker(String(line)))
                return text.isEmpty ? nil : text
            }
            .joined(separator: ", ")
    }

    /// 줄에 보일 글. `match`(펴 놓은 글에서 맞은 자리)가 있으면 그 자리에서 시작한다.
    static func display(_ flattened: String, match: Range<Int>?) -> (text: String, highlight: Range<Int>?) {
        guard let match else { return (String(flattened.prefix(displayLimit)), nil) }
        let text = String(flattened.dropFirst(match.lowerBound).prefix(displayLimit))
        return (text, 0..<min(match.count, text.count))
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
