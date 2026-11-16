import Foundation

/// 선택 없이 서식 단축키를 눌러 정해 둔 "다음에 칠 글자의 서식". 원문에는 아직 아무것도 없고,
/// 글자를 칠 때 기호를 넣는다. 커서를 옮기거나 다른 편집을 하면 사라진다.
nonisolated struct TypingMarks: Equatable, Sendable {
    /// 커서 자리의 서식과 다르게 정한 것만 값이 있다.
    var bold: Bool?
    var strike: Bool?
    var code: Bool?
    /// 형광펜 색 번호. 0은 형광펜 없음.
    var highlight: Int?

    var isEmpty: Bool { bold == nil && strike == nil && code == nil && highlight == nil }

    subscript(wrap: EditorCommands.Wrap) -> Bool? {
        get {
            switch wrap {
            case .bold: bold
            case .strike: strike
            case .code: code
            }
        }
        set {
            switch wrap {
            case .bold: bold = newValue
            case .strike: strike = newValue
            case .code: code = newValue
            }
        }
    }
}

/// 선택 없이 서식 단축키를 눌렀을 때 할 일.
nonisolated enum TypingToggle: Equatable, Sendable {
    /// 커서를 같은 자리의 다른 원문 위치로 옮긴다(구간의 끝에서 안팎을 오간다).
    case move(Int)
    /// 다음에 칠 글자의 서식을 이렇게 정해 둔다.
    case marks(TypingMarks)
    /// 할 수 없다.
    case unavailable
}

nonisolated extension EditorCommands {
    /// 굵게, 취소선, 인라인 코드를 커서 자리에서 켜고 끈다.
    ///
    /// - 그 서식 구간의 끝(또는 앞)에 있으면 구간 밖으로 나간다: 이어 치는 글자는 서식이 없다.
    /// - 그 서식 구간의 바로 바깥에 있으면 안으로 들어간다: 이어 치는 글자는 그 구간에 붙는다.
    /// - 구간 한가운데에서 끄면, 글자를 칠 때 구간을 나누고 그 사이에 넣는다.
    /// - 그 밖에는 글자를 칠 때 새 구간을 만든다.
    static func toggleTyping(_ doc: MarkdownDocument, caret: Int, _ wrap: Wrap, marks: TypingMarks) -> TypingToggle {
        let line = doc.line(at: caret)
        guard !line.kind.isCode, caret >= line.contentStart, line.marker(enclosing: caret) == nil else { return .unavailable }
        var marks = marks
        if marks[wrap] != nil {
            marks[wrap] = nil
            return .marks(marks)
        }
        let containing = line.spansContaining(caret)
        if let span = containing.first(where: { wrap.matches($0.kind) }) {
            if line.visualEnd(from: caret) >= NSMaxRange(span.contentRange) { return .move(NSMaxRange(span.range)) }
            if line.visualStart(from: caret) <= span.contentRange.location { return .move(span.range.location) }
            // 안쪽에 다른 구간이 겹쳐 있으면 바깥 구간만 나눌 수 없다.
            guard containing.first == span else { return .unavailable }
            marks[wrap] = false
            return .marks(marks)
        }
        let spans = line.markedSpans.filter { wrap.matches($0.kind) }
        if let next = spans.first(where: { caret <= $0.range.location && line.visualEnd(from: caret) >= $0.contentRange.location }) {
            return .move(next.contentRange.location)
        }
        if let previous = spans.last(where: { NSMaxRange($0.range) <= caret && line.visualStart(from: caret) <= NSMaxRange($0.contentRange) }) {
            return .move(NSMaxRange(previous.contentRange))
        }
        if wrap != .code, containing.contains(where: { $0.kind == .code }) { return .unavailable }
        marks[wrap] = true
        return .marks(marks)
    }

    /// 형광펜을 커서 자리에서 돌린다: 없음, 노랑, 회색, 로즈, 블루, 다시 없음.
    static func cycleTypingHighlight(_ doc: MarkdownDocument, caret: Int, marks: TypingMarks) -> TypingToggle {
        let line = doc.line(at: caret)
        guard !line.kind.isCode, caret >= line.contentStart, line.marker(enclosing: caret) == nil else { return .unavailable }
        let containing = line.spansContaining(caret)
        guard !containing.contains(where: { $0.kind == .code }) else { return .unavailable }
        let base = containing.lazy.compactMap { span -> Int? in
            if case .highlight(let number) = span.kind { number } else { nil }
        }.first ?? 0
        let current = marks.highlight ?? base
        let next = current >= 4 ? 0 : current + 1
        var marks = marks
        marks.highlight = next == base ? nil : next
        return .marks(marks)
    }

    /// 정해 둔 서식대로 글자를 칠 자리를 만드는 편집. 빈 기호 쌍을 넣고 커서를 그 사이에 둔다
    /// (바꿔 쓸 글이 비어 있으면 커서만 옮긴다). 만들 수 없으면 `nil`.
    /// 조합(한글 입력)을 시작하기 직전에 쓴다. 글자를 바로 넣을 때는 `typing`을 쓴다.
    static func materialize(_ doc: MarkdownDocument, caret: Int, marks: TypingMarks) -> TextEdit? {
        guard let place = typingPlace(doc, caret: caret, marks: marks) else { return nil }
        return TextEdit(
            range: NSRange(location: place.location, length: 0),
            replacement: place.before + place.after,
            selection: NSRange(location: place.location + place.before.utf16.count, length: 0)
        )
    }

    /// 정해 둔 서식으로 `text`를 넣는 편집(기호와 글자가 한 번의 편집이다). 그 서식으로 넣을 수 없으면 `nil`
    /// (서식 없이 넣는다): 기호가 기호로 읽히지 않는 자리(낱말 한가운데)이거나 글이 공백으로 시작하거나 끝난다.
    ///
    /// 여러 줄의 글은 줄마다 따로 감싼다(구간은 줄을 넘지 못한다). 빈 줄은 감싸지 않는다.
    static func typing(_ doc: MarkdownDocument, _ text: String, caret: Int, marks: TypingMarks) -> TextEdit? {
        guard let place = typingPlace(doc, caret: caret, marks: marks) else { return nil }
        let opens = place.opens.joined()
        let closes = place.closes.joined()
        if text.contains("\n") {
            let lines = text.components(separatedBy: "\n")
            // 첫 줄은 커서 앞의 글에 붙는다. 거기서 기호가 읽히지 않으면(영문자 뒤의 여러 낱말) 그 줄은 감싸지 않는다.
            let firstIsRead = lines.first.map { first in
                marksAreRecognized(
                    doc,
                    .insert(opens + first + closes, replacing: NSRange(location: place.location, length: 0)),
                    markers: [
                        NSRange(location: 0, length: opens.utf16.count),
                        NSRange(location: opens.utf16.count + first.utf16.count, length: closes.utf16.count),
                    ]
                )
            } ?? true
            let wrapped = lines.enumerated()
                .map { index, line in
                    line.trimmingCharacters(in: .whitespaces).isEmpty || (index == 0 && !firstIsRead) ? line : opens + line + closes
                }
                .joined(separator: "\n")
            // 커서를 안에 둔 구간은 `replacing`이 줄바꿈 앞에서 닫고 뒤에서 다시 연다.
            return insert(doc, wrapped, replacing: NSRange(location: place.location, length: 0))
        }
        let inserted = place.before + text
        let edit = TextEdit(
            range: NSRange(location: place.location, length: 0),
            replacement: inserted + place.after,
            selection: NSRange(location: place.location + inserted.utf16.count, length: 0)
        )
        var markers: [NSRange] = []
        var offset = 0
        for marker in [place.exitClose] + place.opens {
            markers.append(NSRange(location: offset, length: marker.utf16.count))
            offset += marker.utf16.count
        }
        offset += text.utf16.count
        for marker in place.closes + [place.exitOpen] {
            markers.append(NSRange(location: offset, length: marker.utf16.count))
            offset += marker.utf16.count
        }
        return marksAreRecognized(doc, edit, markers: markers) ? edit : nil
    }

    /// 정해 둔 서식으로 글자를 넣을 자리와, 그 앞뒤에 넣을 기호.
    struct TypingPlace: Equatable, Sendable {
        var location: Int
        /// 구간 한가운데에서 끄는 서식: 그 구간을 여기서 닫고(`exitClose`) 글자 뒤에서 다시 연다(`exitOpen`).
        var exitClose = ""
        var exitOpen = ""
        /// 새로 여는 구간들의 기호. 바깥 것부터.
        var opens: [String] = []
        /// 안쪽 것부터.
        var closes: [String] = []

        var before: String { exitClose + opens.joined() }
        var after: String { closes.joined() + exitOpen }
    }

    static func typingPlace(_ doc: MarkdownDocument, caret: Int, marks: TypingMarks) -> TypingPlace? {
        let line = doc.line(at: caret)
        guard !marks.isEmpty, !line.kind.isCode, caret >= line.contentStart, line.marker(enclosing: caret) == nil else { return nil }
        let containing = line.spansContaining(caret)
        var place = TypingPlace(location: caret)
        var remaining = containing

        // 끄는 서식: 그 구간에서 나가거나, 한가운데면 구간을 나눈다.
        let exits = containing.filter { span in
            switch span.kind {
            case .bold: marks.bold == false
            case .strike: marks.strike == false
            case .code: marks.code == false
            case .highlight(let number): marks.highlight != nil && marks.highlight != number
            case .link, .escape: false
            }
        }
        if let outer = exits.last {
            if line.visualEnd(from: caret) >= NSMaxRange(outer.contentRange) {
                place.location = NSMaxRange(outer.range)
                remaining = line.spansContaining(place.location)
            } else if line.visualStart(from: caret) <= outer.contentRange.location {
                place.location = outer.range.location
                remaining = line.spansContaining(place.location)
            } else if containing.first == outer {
                place.exitClose = doc.string(in: outer.closeMarker)
                place.exitOpen = doc.string(in: outer.openMarker)
                remaining.removeFirst()
            } else {
                return nil
            }
        }

        // 켜는 서식: 새 구간을 연다. 인라인 코드 안에는 열지 않는다.
        if !remaining.contains(where: { $0.kind == .code }) {
            func has(_ matches: (InlineSpan.Kind) -> Bool) -> Bool { remaining.contains { matches($0.kind) } }
            if let number = marks.highlight, number > 0, !has({ $0 == .highlight(number) }) {
                place.opens.append("==")
                place.closes.insert(highlightClose(number), at: 0)
            }
            for wrap in [Wrap.bold, .strike, .code] where marks[wrap] == true && !has(wrap.matches) {
                place.opens.append(wrap.marker)
                place.closes.insert(wrap.marker, at: 0)
            }
        }
        guard !place.before.isEmpty || !place.after.isEmpty || place.location != caret else { return nil }
        return place
    }
}
