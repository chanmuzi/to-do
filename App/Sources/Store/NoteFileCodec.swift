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
///
/// 아는 항목은 줄 맨 앞(들여쓰기 없음)에서 시작하는 `title`, `space`, `color`, `reminder`, `created`뿐이다.
/// 들여쓴 줄과 그 밖의 줄은 모르는 줄로 두고 건드리지 않는다.
/// 이미 있는 파일을 고쳐 쓸 때는 `encode(_:over:)`를 쓴다.
enum NoteFileCodec {
    static let delimiter = "---"
    static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"

    /// 머리에서 이 앱이 아는 항목. 순서는 새 파일에 쓰는 순서다.
    enum Key: String, CaseIterable {
        case title, space, color, reminder, created
    }

    /// 새 파일의 표기.
    static func encode(_ content: NoteFileContent) -> String {
        let known = Key.allCases.compactMap { line($0, in: content) }
        let lines = [delimiter] + known + content.unknownLines + [delimiter]
        return lines.joined(separator: "\n") + "\n" + content.body
    }

    static func decode(_ text: String) -> NoteFileContent {
        guard let header = Header(text) else { return NoteFileContent(body: text) }
        var content = NoteFileContent(body: String(text[header.bodyStart...]))
        for line in header.lines {
            guard let field = field(line) else {
                content.unknownLines.append(line)
                continue
            }
            switch field.key {
            case .title: content.title = field.value
            case .space: content.spaceID = field.value.isEmpty ? nil : SpaceID(rawValue: field.value)
            case .color: content.colorID = field.value.isEmpty ? nil : PaletteID(rawValue: field.value)
            // 읽지 못한 날짜 줄은 값 없음으로 읽고, 다시 쓸 때 `encode(_:over:)`가 원래 줄을 남긴다.
            case .reminder: content.reminder = parseDate(field.value)
            case .created: content.created = parseDate(field.value)
            }
        }
        return content
    }

    /// 날짜는 초 단위까지만 적는다. 저장 전후가 같도록 미리 초 아래를 버릴 때 쓴다.
    static func truncatedToSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - 줄 하나

    /// 머리 줄이 아는 항목이면 그 키와 값. 들여쓴 줄, 콜론 없는 줄, 모르는 키는 `nil`.
    static func field(_ line: String) -> (key: Key, value: String)? {
        guard let colon = line.firstIndex(of: ":"),
              let key = Key(rawValue: String(line[..<colon]))
        else { return nil }
        return (key, unquoted(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
    }

    /// 항목 하나를 새로 적은 줄. 값이 없으면 `nil`(제목은 비어 있어도 적는다).
    static func line(_ key: Key, in content: NoteFileContent) -> String? {
        switch key {
        case .title: "title: \(quoted(content.title))"
        case .space: content.spaceID.map { "space: \(quoted($0.rawValue))" }
        case .color: content.colorID.map { "color: \($0.rawValue)" }
        case .reminder: content.reminder.map { "reminder: \(format($0))" }
        case .created: content.created.map { "created: \(format($0))" }
        }
    }

    /// ISO 8601 날짜를 읽는다. 초 아래 자리(`…00.123Z`)와 날짜만 있는 값(`2026-11-17`, UTC 자정)도 받는다.
    static func parseDate(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        // 날짜만 읽는 방식은 뒤에 딸린 글자를 무시하므로 모양이 정확히 `YYYY-MM-DD`일 때만 쓴다.
        guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
        return try? Date(value, strategy: Date.ISO8601FormatStyle().year().month().day())
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
}
