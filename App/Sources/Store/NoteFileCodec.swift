import Foundation
import Models

/// 노트 파일 한 개의 내용. 머리(frontmatter)와 본문.
struct NoteFileContent: Equatable {
    var title: String = ""
    var spaceID: SpaceID?
    var colorID: PaletteID?
    var reminder: Date?
    var created: Date?
    /// 이 앱이 모르는 머리 줄. 다시 쓸 때 그대로 둔다.
    var unknownLines: [String] = []
    /// 본문 원문.
    var body: String = ""
}

/// 노트 파일 표기(D-003).
///
/// ```
/// ---
/// title: "제목"
/// space: <스페이스 id>
/// color: tint-3
/// reminder: 2026-11-17T06:00:00Z
/// created: 2026-11-16T12:08:00Z
/// ---
/// 본문(닫는 `---` 줄 바로 다음 글자부터 파일 끝까지, 그대로)
/// ```
///
/// 값이 없는 항목은 줄을 쓰지 않는다. 제목은 JSON 문자열로 따옴표에 넣어 어떤 글자든 담는다.
/// 머리가 없는 파일은 전체를 본문으로 읽는다.
enum NoteFileCodec {
    private static let delimiter = "---"

    static func encode(_ content: NoteFileContent) -> String {
        var lines = [delimiter, "title: \(quoted(content.title))"]
        if let space = content.spaceID { lines.append("space: \(quoted(space.rawValue))") }
        if let color = content.colorID { lines.append("color: \(color.rawValue)") }
        if let reminder = content.reminder { lines.append("reminder: \(format(reminder))") }
        if let created = content.created { lines.append("created: \(format(created))") }
        lines.append(contentsOf: content.unknownLines)
        lines.append(delimiter)
        return lines.joined(separator: "\n") + "\n" + content.body
    }

    static func decode(_ text: String) -> NoteFileContent {
        guard let (headerLines, bodyStart) = splitHeader(text) else {
            return NoteFileContent(body: text)
        }
        var content = NoteFileContent(body: String(text[bodyStart...]))
        for line in headerLines {
            guard let colon = line.firstIndex(of: ":") else {
                content.unknownLines.append(line)
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = unquoted(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            switch key {
            case "title": content.title = value
            case "space": content.spaceID = value.isEmpty ? nil : SpaceID(rawValue: value)
            case "color": content.colorID = value.isEmpty ? nil : PaletteID(rawValue: value)
            case "reminder": content.reminder = parseDate(value)
            case "created": content.created = parseDate(value)
            default: content.unknownLines.append(line)
            }
        }
        return content
    }

    /// 날짜는 초 단위까지만 적는다. 저장 전후가 같도록 미리 초 아래를 버릴 때 쓴다.
    static func truncatedToSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - 내부

    /// 머리 줄들과 본문이 시작하는 자리. 머리가 없으면 `nil`.
    /// 줄바꿈 바이트 단위로 훑어 본문의 글자를 건드리지 않는다.
    private static func splitHeader(_ text: String) -> (lines: [String], bodyStart: String.Index)? {
        let utf8 = text.utf8
        var lines: [String] = []
        var cursor = utf8.startIndex
        var isFirst = true
        while cursor < utf8.endIndex {
            guard let newline = utf8[cursor...].firstIndex(of: UInt8(ascii: "\n")) else {
                // 마지막 줄이 줄바꿈 없이 끝났다. 닫는 구분선이면 본문은 비어 있다.
                let last = line(utf8[cursor...])
                return !isFirst && last == delimiter ? (lines, utf8.endIndex) : nil
            }
            let current = line(utf8[cursor..<newline])
            let next = utf8.index(after: newline)
            if isFirst {
                guard current == delimiter else { return nil }
                isFirst = false
            } else if current == delimiter {
                return (lines, next)
            } else {
                lines.append(current)
            }
            cursor = next
        }
        return nil
    }

    private static func line(_ bytes: Substring.UTF8View) -> String {
        var string = String(decoding: bytes, as: UTF8.self)
        if string.unicodeScalars.last == "\r" { string.unicodeScalars.removeLast() }
        return string
    }

    private static func quoted(_ string: String) -> String {
        // 문자열 하나를 JSON으로 쓰는 일은 실패하지 않는다.
        let data = try! JSONEncoder().encode(string)
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
    }

    private static func unquoted(_ value: String) -> String {
        guard value.hasPrefix("\""), let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data)
        else { return value }
        return decoded
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func parseDate(_ value: String) -> Date? {
        try? Date(value, strategy: .iso8601)
    }
}
