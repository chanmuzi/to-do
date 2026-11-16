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
    static func materialize(_ doc: MarkdownDocument, caret: Int, marks: TypingMarks) -> TextEdit? {
        let line = doc.line(at: caret)
        guard !marks.isEmpty, !line.kind.isCode, caret >= line.contentStart, line.marker(enclosing: caret) == nil else { return nil }
        let containing = line.spansContaining(caret)
        var location = caret
        var before = ""
        var after = ""
        var remaining = containing

        // 끄는 서식: 그 구간에서 나가거나, 한가운데면 구간을 나눈다.
        let exits = containing.filter { span in
            switch span.kind {
            case .bold: marks.bold == false
            case .strike: marks.strike == false
            case .code: marks.code == false
            case .highlight(let number): marks.highlight != nil && marks.highlight != number
            case .link: false
            }
        }
        if let outer = exits.last {
            if line.visualEnd(from: caret) >= NSMaxRange(outer.contentRange) {
                location = NSMaxRange(outer.range)
                remaining = line.spansContaining(location)
            } else if line.visualStart(from: caret) <= outer.contentRange.location {
                location = outer.range.location
                remaining = line.spansContaining(location)
            } else if containing.first == outer {
                before = doc.string(in: outer.closeMarker)
                after = doc.string(in: outer.openMarker)
                remaining.removeFirst()
            } else {
                return nil
            }
        }

        // 켜는 서식: 새 구간을 연다. 인라인 코드 안에는 열지 않는다.
        if !remaining.contains(where: { $0.kind == .code }) {
            var opens = ""
            var closes = ""
            func has(_ matches: (InlineSpan.Kind) -> Bool) -> Bool { remaining.contains { matches($0.kind) } }
            if let number = marks.highlight, number > 0, !has({ $0 == .highlight(number) }) {
                opens += "=="
                closes = highlightClose(number) + closes
            }
            for wrap in [Wrap.bold, .strike, .code] where marks[wrap] == true && !has(wrap.matches) {
                opens += wrap.marker
                closes = wrap.marker + closes
            }
            before += opens
            after = closes + after
        }
        guard !before.isEmpty || !after.isEmpty || location != caret else { return nil }
        return TextEdit(
            range: NSRange(location: location, length: 0),
            replacement: before + after,
            selection: NSRange(location: location + before.utf16.count, length: 0)
        )
    }
}
