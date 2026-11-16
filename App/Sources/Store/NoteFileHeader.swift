import Foundation

extension NoteFileCodec {
    /// 파일에서 찾은 머리. 줄바꿈 바이트 단위로 훑어 본문의 글자를 건드리지 않는다.
    struct Header {
        /// 여는 `---`와 닫는 `---` 사이의 줄(줄바꿈 제외).
        let lines: [String]
        /// 본문이 시작하는 자리.
        let bodyStart: String.Index
        /// 파일이 UTF-8 BOM으로 시작했다.
        let hasByteOrderMark: Bool
        /// 머리에서 쓰인 줄바꿈(`\n` 또는 `\r\n`).
        let newline: String
        /// 닫는 `---` 뒤에 줄바꿈 없이 파일이 끝났다.
        let endsWithoutNewline: Bool

        /// 머리가 없으면 `nil`. 첫 줄이 `---`이고 닫는 `---` 줄이 있어야 머리다. 맨 앞의 BOM은 건너뛴다.
        init?(_ text: String) {
            let utf8 = text.utf8
            let hasByteOrderMark = text.unicodeScalars.first == NoteFileCodec.byteOrderMark
            var cursor = hasByteOrderMark ? text.unicodeScalars.index(after: text.startIndex) : utf8.startIndex
            var lines: [String] = []
            var newline: String?
            var isFirst = true
            while cursor < utf8.endIndex {
                guard let lineEnd = utf8[cursor...].firstIndex(of: UInt8(ascii: "\n")) else {
                    // 마지막 줄이 줄바꿈 없이 끝났다. 닫는 구분선이면 본문은 비어 있다.
                    guard !isFirst, Self.line(utf8[cursor...]).text == NoteFileCodec.delimiter else { return nil }
                    self.init(
                        lines: lines, bodyStart: utf8.endIndex, hasByteOrderMark: hasByteOrderMark,
                        newline: newline ?? "\n", endsWithoutNewline: true
                    )
                    return
                }
                let current = Self.line(utf8[cursor..<lineEnd])
                let next = utf8.index(after: lineEnd)
                if isFirst {
                    guard current.text == NoteFileCodec.delimiter else { return nil }
                    newline = current.endedWithCarriageReturn ? "\r\n" : "\n"
                    isFirst = false
                } else if current.text == NoteFileCodec.delimiter {
                    self.init(
                        lines: lines, bodyStart: next, hasByteOrderMark: hasByteOrderMark,
                        newline: newline ?? "\n", endsWithoutNewline: false
                    )
                    return
                } else {
                    lines.append(current.text)
                }
                cursor = next
            }
            return nil
        }

        private init(
            lines: [String], bodyStart: String.Index, hasByteOrderMark: Bool,
            newline: String, endsWithoutNewline: Bool
        ) {
            self.lines = lines
            self.bodyStart = bodyStart
            self.hasByteOrderMark = hasByteOrderMark
            self.newline = newline
            self.endsWithoutNewline = endsWithoutNewline
        }

        private static func line(_ bytes: Substring.UTF8View) -> (text: String, endedWithCarriageReturn: Bool) {
            var string = String(decoding: bytes, as: UTF8.self)
            guard string.unicodeScalars.last == "\r" else { return (string, false) }
            string.unicodeScalars.removeLast()
            return (string, true)
        }
    }

    /// 이미 있는 파일(`existing`)을 `content`의 값으로 고쳐 쓴 글.
    ///
    /// 값이 바뀐 항목의 줄만 새로 적는다. 나머지 줄은 순서와 표기를 그대로 둔다.
    /// - 값이 그대로인 줄은 원래 줄 그대로다(손으로 적은 표기, 초 아래 자리가 있는 날짜,
    ///   읽지 못한 날짜 줄이 여기에 든다. 읽지 못한 `reminder`는 리마인더를 새로 정할 때만 바뀐다).
    /// - `created`는 이 앱에서 바꿀 수 없는 값이라 줄이 있으면 언제나 그대로 둔다.
    /// - 모르는 줄, BOM, 머리의 줄바꿈 종류는 그대로 둔다.
    /// - 머리에 없던 항목은 마지막 아는 줄 다음에 넣는다.
    /// - `existing`에 머리가 없으면 새 파일의 표기(`encode(_:)`)로 쓴다.
    static func encode(_ content: NoteFileContent, over existing: String) -> String {
        guard let header = Header(existing) else { return encode(content) }
        let fields = header.lines.map(field)
        var lastIndex: [Key: Int] = [:]
        for (index, field) in fields.enumerated() {
            if let field { lastIndex[field.key] = index }
        }

        var lines: [String] = []
        var insertionPoint = 0
        for (index, original) in header.lines.enumerated() {
            // 같은 키가 여러 번 나오면 읽을 때 마지막 줄이 이긴다. 고쳐 쓰는 것도 마지막 줄이다.
            guard let field = fields[index], lastIndex[field.key] == index else {
                lines.append(original)
                continue
            }
            if let line = rewritten(original, field: field, content: content) { lines.append(line) }
            insertionPoint = lines.count
        }
        let added = Key.allCases.filter { lastIndex[$0] == nil }.compactMap { key -> String? in
            if key == .title, content.title.isEmpty { return nil }
            return line(key, in: content)
        }
        lines.insert(contentsOf: added, at: insertionPoint)

        let head = ([delimiter] + lines + [delimiter]).joined(separator: header.newline)
        let prefix = header.hasByteOrderMark ? String(Character(byteOrderMark)) : ""
        let closing = header.endsWithoutNewline && content.body.isEmpty ? "" : header.newline
        return prefix + head + closing + content.body
    }

    /// 아는 항목의 줄을 고쳐 쓴다. 값이 그대로면 원래 줄, 값이 없어졌으면 `nil`.
    private static func rewritten(
        _ original: String, field: (key: Key, value: String), content: NoteFileContent
    ) -> String? {
        let isUnchanged: Bool
        switch field.key {
        case .title: isUnchanged = field.value == content.title
        case .space: isUnchanged = field.value == (content.spaceID?.rawValue ?? "")
        case .color: isUnchanged = field.value == (content.colorID?.rawValue ?? "")
        case .reminder: isUnchanged = parseDate(field.value) == content.reminder
        case .created: isUnchanged = true
        }
        return isUnchanged ? original : line(field.key, in: content)
    }
}
