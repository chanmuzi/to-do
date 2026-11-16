import Foundation

/// 글에서 날짜와 시각 조각을 찾는다. 조각을 잇고 날짜로 푸는 일은 `DateTimeParser`가 한다.
/// 받는 글은 `NormalizedText`로 고른 글이다.
///
/// 보통 글을 잘못 읽지 않도록 조각마다 앞뒤 글자를 가린다: 숫자나 점에 붙은 수(`v2.3.1`, `2.5`),
/// 단위가 다른 말(`3시간`, `20일간`, `3시즌`), 낱말 속의 글자(`수정오류`의 `정오`, `내일배움카드`의 `내일`)는 조각이 아니다.
/// 무늬는 `DateTimeLexer+Time`, `+Relative`, `+Date`에 나눠 둔다.
nonisolated enum DateTimeLexer {
    static func pieces(in text: String) -> [DateTimePiece] {
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        var found: [(piece: DateTimePiece, order: Int)] = []
        for (order, rule) in rules.enumerated() {
            for result in rule.regex.matches(in: text, range: whole) {
                guard var piece = rule.build(Match(result: result, source: source)) else { continue }
                piece.range = result.range
                found.append((piece, order))
            }
        }
        // 겹치는 조각은 앞에서 시작하는 것, 같은 자리면 긴 것을 남긴다(`11월 20일`이 `20일`보다, `3일 뒤`가 `3일`보다 먼저).
        let ordered = found.sorted {
            if $0.piece.range.location != $1.piece.range.location {
                return $0.piece.range.location < $1.piece.range.location
            }
            if $0.piece.range.length != $1.piece.range.length {
                return $0.piece.range.length > $1.piece.range.length
            }
            return $0.order < $1.order
        }
        var kept: [DateTimePiece] = []
        for (piece, _) in ordered where piece.range.location >= (kept.last.map { NSMaxRange($0.range) } ?? 0) {
            kept.append(piece)
        }
        return kept
    }

    // MARK: - 규칙

    /// 무늬에 맞은 한 곳.
    struct Match {
        let result: NSTextCheckingResult
        let source: NSString

        func string(_ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }

        func int(_ index: Int) -> Int? { string(index).flatMap { Int($0) } }

        func has(_ index: Int) -> Bool { result.range(at: index).location != NSNotFound }

        /// 맞은 곳 바로 앞의 글이 `regex`로 끝나는지(무늬는 `$`로 끝낸다).
        func isPreceded(by regex: NSRegularExpression) -> Bool {
            let before = NSRange(location: 0, length: result.range.location)
            return regex.firstMatch(in: source as String, range: before) != nil
        }

        /// 맞은 곳 바로 뒤의 글이 `regex`로 시작하는지(무늬는 `^`로 시작한다).
        func isFollowed(by regex: NSRegularExpression) -> Bool {
            let end = NSMaxRange(result.range)
            let after = NSRange(location: end, length: source.length - end)
            return regex.firstMatch(in: source as String, options: [.anchored], range: after) != nil
        }
    }

    struct Rule {
        let regex: NSRegularExpression
        let build: @Sendable (Match) -> DateTimePiece?

        init(_ pattern: String, caseInsensitive: Bool = false, build: @escaping @Sendable (Match) -> DateTimePiece?) {
            regex = DateTimeLexer.regex(pattern, caseInsensitive: caseInsensitive)
            self.build = build
        }
    }

    static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("날짜 무늬가 잘못됐습니다: \(pattern): \(error)")
        }
    }

    private static let rules: [Rule] = timeRules + relativeRules + dateRules

    // MARK: - 조각 만들기

    static let placeholder = NSRange(location: 0, length: 0)

    static func piece(
        _ kind: DateTimePiece.Kind, requirement: DateTimePiece.Requirement = .none, impliedPart: DayPart? = nil
    ) -> DateTimePiece {
        DateTimePiece(kind: kind, range: placeholder, requirement: requirement, impliedPart: impliedPart)
    }

    static func date(_ spec: DateSpec, requirement: DateTimePiece.Requirement = .none) -> DateTimePiece {
        piece(.date(spec), requirement: requirement)
    }

    /// 적은 시각을 가린다. 달력에 없는 시각(25시, 61분)과 맞지 않는 짝(오전 15시)은 `nil`.
    /// - Parameters:
    ///   - leadingZero: `09:00`처럼 시 앞에 0을 붙였다(24시간제다).
    ///   - allows24: `24:00`을 받는다(`24시`는 받지 않는다. `24시 편의점`).
    static func timeSpec(
        hour: Int, minute: Int = 0, part: DayPart? = nil, leadingZero: Bool = false, allows24: Bool = false
    ) -> TimeSpec? {
        guard (0..<60).contains(minute) else { return nil }
        var spec = TimeSpec(hour: hour, minute: minute, part: part)
        if let part {
            guard part.hour24(hour) != nil else { return nil }
            return spec
        }
        switch hour {
        case 1...12: spec.isClock24 = leadingZero
        case 0, 13...23: spec.isClock24 = true
        case 24 where allows24 && minute == 0: spec.isClock24 = true
        default: return nil
        }
        return spec
    }

    // MARK: - 여러 무늬가 함께 쓰는 낱말

    static let dayParts = "오전|오후|아침|낮|점심|저녁|밤|새벽"
    static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    static let englishWeekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    static let englishWeekdayPattern = "mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?"
        + "|fri(?:day)?|sat(?:urday)?|sun(?:day)?"
    /// 낱말 뒤가 글의 끝, 한글이 아닌 글자, 또는 조사일 때만.
    static let wordEnd = #"(?=$|[^가-힣]|에|까지|부터|쯤|은|는|이|가|도)"#
}
