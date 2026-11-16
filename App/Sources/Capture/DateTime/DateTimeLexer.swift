import Foundation

/// 글에서 날짜와 시각 조각을 찾는다. 조각을 잇고 날짜로 푸는 일은 `DateTimeParser`가 한다.
///
/// 보통 글을 잘못 읽지 않도록 조각마다 앞뒤 글자를 가린다: 숫자나 점에 붙은 수(`v2.3.1`, `2.5`),
/// 단위가 다른 말(`3시간`, `20일간`), 낱말 속의 글자(`수정오류`의 `정오`)는 조각이 아니다.
nonisolated enum DateTimeLexer {
    static func pieces(in text: String) -> [DateTimePiece] {
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        var found: [DateTimePiece] = []
        for rule in rules {
            for match in rule.regex.matches(in: text, range: whole) {
                let groups = Groups(match: match, source: source)
                guard var piece = rule.build(groups) else { continue }
                piece.range = match.range
                found.append(piece)
            }
        }
        // 겹치는 조각은 앞에서 시작하는 것, 같은 자리면 긴 것을 남긴다(`11월 20일`이 `20일`보다, `3일 뒤`가 `3일`보다 먼저).
        let ordered = found.sorted {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location : $0.range.length > $1.range.length
        }
        var kept: [DateTimePiece] = []
        for piece in ordered where piece.range.location >= (kept.last.map { NSMaxRange($0.range) } ?? 0) {
            kept.append(piece)
        }
        return kept
    }

    // MARK: - 규칙

    private struct Groups {
        let match: NSTextCheckingResult
        let source: NSString

        func string(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }

        func int(_ index: Int) -> Int? { string(index).flatMap { Int($0) } }
    }

    private struct Rule {
        let regex: NSRegularExpression
        let build: @Sendable (Groups) -> DateTimePiece?

        init(_ pattern: String, caseInsensitive: Bool = false, build: @escaping @Sendable (Groups) -> DateTimePiece?) {
            do {
                regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
            } catch {
                preconditionFailure("날짜 무늬가 잘못됐습니다: \(pattern): \(error)")
            }
            self.build = build
        }
    }

    private static let placeholder = NSRange(location: 0, length: 0)

    private static func time(_ spec: TimeSpec) -> DateTimePiece? {
        guard (0...24).contains(spec.hour), (0..<60).contains(spec.minute), spec.hour < 24 || spec.minute == 0
        else { return nil }
        if let part = spec.part, part.hour24(spec.hour) == nil { return nil }
        var checked = spec
        // 24시간제로 적은 시각에는 뒤따르는 말을 붙이지 않는다.
        if let trailing = spec.trailingPart, trailing.hour24(spec.hour) == nil || !(1...12).contains(spec.hour) {
            checked.trailingPart = nil
        }
        return DateTimePiece(kind: .time(checked), range: placeholder)
    }

    private static func date(
        _ spec: DateSpec, requirement: DateTimePiece.Requirement = .none
    ) -> DateTimePiece {
        DateTimePiece(kind: .date(spec), range: placeholder, requirement: requirement)
    }

    private static let dayParts = "오전|오후|아침|낮|점심|저녁|밤|새벽"
    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    private static let englishWeekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    /// 낱말 뒤가 글의 끝, 한글이 아닌 글자, 또는 조사일 때만.
    private static let wordEnd = #"(?=$|[^가-힣]|에|까지|부터|쯤|은|는|이|가|도)"#

    private static let rules: [Rule] = timeRules + relativeRules + dateRules

    private static let timeRules: [Rule] = [
        // 3시, 오후 3시, 10시 반, 3시 30분, PM 3시, 7시 (저녁)
        Rule(#"(?:("# + dayParts + #"|AM|PM)\s*)?(?<![\d.:])(\d{1,2})시(?!간)(?:\s*(\d{1,2})분|\s*(반))?"#
            + #"(?=(?:\s*("# + dayParts + #")(?![가-힣]))?)"#) { groups in
            guard let hour = groups.int(2) else { return nil }
            return time(TimeSpec(
                hour: hour, minute: groups.string(4) != nil ? 30 : (groups.int(3) ?? 0),
                part: groups.string(1).flatMap(DayPart.init(word:)),
                trailingPart: groups.string(5).flatMap(DayPart.init(word:))
            ))
        },
        // 15:00, 오후 3:30, 3:30 PM, PM 3:30
        Rule(#"(?:("# + dayParts + #"|AM|PM)\s*)?(?<![\d.:])(\d{1,2}):(\d{2})(?![\d:])"#
            + #"(?:\s*([aApP])\.?[mM]\.?(?![A-Za-z]))?"#) { groups in
            guard let hour = groups.int(2), let minute = groups.int(3) else { return nil }
            let part = (groups.string(4) ?? groups.string(1)).flatMap(DayPart.init(word:))
            return time(TimeSpec(hour: hour, minute: minute, part: part))
        },
        // 3pm, 3 PM, 10 a.m.
        Rule(#"(?<![\d.:A-Za-z])(\d{1,2})\s*([aApP])\.?[mM]\.?(?![A-Za-z])"#) { groups in
            guard let hour = groups.int(1), (1...12).contains(hour) else { return nil }
            return time(TimeSpec(hour: hour, minute: 0, part: groups.string(2).flatMap(DayPart.init(word:))))
        },
        // PM 3 (대문자일 때만: "I am 3"을 읽지 않는다)
        Rule(#"(?<![A-Za-z0-9])(AM|PM)\s*(\d{1,2})(?![\d:시.])"#) { groups in
            guard let hour = groups.int(2), (1...12).contains(hour) else { return nil }
            return time(TimeSpec(hour: hour, minute: 0, part: groups.string(1).flatMap(DayPart.init(word:))))
        },
        Rule(#"(?<![가-힣A-Za-z0-9])(정오|자정)"# + wordEnd) { groups in
            time(TimeSpec(hour: 12, minute: 0, part: groups.string(1) == "정오" ? .afternoon : .night))
        },
        Rule(#"(?<![A-Za-z0-9])(noon|midnight)(?![A-Za-z0-9])"#, caseInsensitive: true) { groups in
            time(TimeSpec(hour: 12, minute: 0, part: groups.string(1)?.lowercased() == "noon" ? .afternoon : .night))
        },
    ]

    private static let relativeRules: [Rule] = [
        // 2시간 뒤, 1시간 30분 후, 1시간 반 뒤
        Rule(#"(?<![\d.])(\d{1,3})\s*시간(?:\s*(\d{1,2})\s*분|\s*(반))?\s*(?:뒤|후|있다가)"# + wordEnd) { groups in
            guard let hours = groups.int(1) else { return nil }
            let minutes = groups.string(3) != nil ? 30 : (groups.int(2) ?? 0)
            guard hours > 0 || minutes > 0 else { return nil }
            return DateTimePiece(kind: .fromNow(TimeInterval(hours * 3600 + minutes * 60)), range: placeholder)
        },
        // 30분 뒤
        Rule(#"(?<![\d.])(\d{1,3})\s*분\s*(?:뒤|후|있다가)"# + wordEnd) { groups in
            guard let minutes = groups.int(1), minutes > 0 else { return nil }
            return DateTimePiece(kind: .fromNow(TimeInterval(minutes * 60)), range: placeholder)
        },
        // in 2 hours, in 30 min, in an hour
        Rule(#"(?<![A-Za-z0-9])in\s+(\d{1,3}|an?)\s*(minutes?|mins?|hours?|hrs?)(?![A-Za-z0-9])"#,
             caseInsensitive: true) { groups in
            let amount = groups.int(1) ?? 1
            guard amount > 0, let unit = groups.string(2)?.lowercased() else { return nil }
            return DateTimePiece(
                kind: .fromNow(TimeInterval(amount * (unit.hasPrefix("m") ? 60 : 3600))), range: placeholder
            )
        },
        // 3일 뒤, 2주 후
        Rule(#"(?<![\d.])(\d{1,3})\s*(일|주)\s*(?:뒤|후)"# + wordEnd) { groups in
            guard let amount = groups.int(1), amount > 0 else { return nil }
            return date(.offsetDays(amount * (groups.string(2) == "주" ? 7 : 1)))
        },
        // in 3 days, in a week
        Rule(#"(?<![A-Za-z0-9])in\s+(\d{1,3}|an?)\s*(days?|weeks?)(?![A-Za-z0-9])"#, caseInsensitive: true) { groups in
            let amount = groups.int(1) ?? 1
            guard amount > 0, let unit = groups.string(2)?.lowercased() else { return nil }
            return date(.offsetDays(amount * (unit.hasPrefix("w") ? 7 : 1)))
        },
    ]

    private static let dateRules: [Rule] = [
        Rule(#"(?<![가-힣])(내일모레|오늘|내일|모레|글피)"#) { groups in
            switch groups.string(1) {
            case "오늘": date(.offsetDays(0), requirement: .needsTime)
            case "내일": date(.offsetDays(1))
            case "모레", "내일모레": date(.offsetDays(2))
            default: date(.offsetDays(3))
            }
        },
        Rule(#"(?<![A-Za-z0-9])(today|tomorrow|tmrw|tmr)(?![A-Za-z0-9])"#, caseInsensitive: true) { groups in
            groups.string(1)?.lowercased() == "today"
                ? date(.offsetDays(0), requirement: .needsTime) : date(.offsetDays(1))
        },
        // 금요일, 이번 주 금요일, 다음 주 월요일
        Rule(#"(?<![가-힣])(?:(이번|다음|다다음)\s*주\s*)?([월화수목금토일])요일"#) { groups in
            guard let index = groups.string(2).flatMap(weekdays.firstIndex(of:)) else { return nil }
            switch groups.string(1) {
            case "이번": return date(.weekday(index, .weeksAhead(0)))
            case "다음": return date(.weekday(index, .weeksAhead(1)))
            case "다다음": return date(.weekday(index, .weeksAhead(2)))
            default: return date(.weekday(index, .upcoming))
            }
        },
        // fri, friday, next mon, this fri
        Rule(#"(?<![A-Za-z0-9])(?:(next|this)\s+)?(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?"#
            + #"|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?![A-Za-z0-9])"#, caseInsensitive: true) { groups in
            guard let word = groups.string(2)?.lowercased(),
                  let index = englishWeekdays.firstIndex(of: String(word.prefix(3))) else { return nil }
            switch groups.string(1)?.lowercased() {
            case "next": return date(.weekday(index, .weeksAhead(1)))
            case "this": return date(.weekday(index, .weeksAhead(0)))
            default:
                // sun, sat은 보통 낱말이기도 하다. 시각이나 범위와 함께 있을 때만 요일로 읽는다.
                return date(.weekday(index, .upcoming), requirement: ["sun", "sat"].contains(word) ? .needsCompany : .none)
            }
        },
        // 2026-11-20, 2026.11.20, 2026/11/20
        Rule(#"(?<![\d\-./])(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)(?![-/.]\d)"#) { groups in
            guard let year = groups.int(1), let month = groups.int(2), let day = groups.int(3) else { return nil }
            return date(.monthDay(month: month, day: day, year: year, loose: false))
        },
        // 11월 20일, 2026년 11월 20일
        Rule(#"(?<![\d.])(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일"#) { groups in
            guard let month = groups.int(2), let day = groups.int(3) else { return nil }
            return date(.monthDay(month: month, day: day, year: groups.int(1), loose: false))
        },
        // 11/20. 분수로 읽힐 말이 뒤따르면(1/2 완료, 1/2 컵) 날짜가 아니다.
        Rule(#"(?<![\d/.A-Za-z])(\d{1,2})/(\d{1,2})(?![\d/])(?!\.\d)"#
            + #"(?!\s*(?:완료|진행|정도|쯤|컵|개|스푼|큰술|작은술|분량|지점|확률|페이지|쪽|씩|배|만큼|가량|크기|사이즈))"#) { groups in
            guard let month = groups.int(1), let day = groups.int(2) else { return nil }
            return date(.monthDay(month: month, day: day, year: nil, loose: true))
        },
        // 11.20. 소수와 가려지지 않아 시각이나 범위와 함께 있을 때만 날짜로 읽는다.
        Rule(#"(?<![\d/.A-Za-z])(\d{1,2})\.(\d{1,2})(?![\d/%])(?!\.\d)"#) { groups in
            guard let month = groups.int(1), let day = groups.int(2) else { return nil }
            return date(.monthDay(month: month, day: day, year: nil, loose: true), requirement: .needsCompany)
        },
        // 20일. 기간이나 차례를 세는 말(20일간, 3일째, 2일 전)은 날짜가 아니다.
        Rule(#"(?<![\d./])(\d{1,2})일(?!간|동안|째|차|치|분|\s*(?:뒤|후|전|동안|간|이상|이내|정도|씩|마다|만에))"#) { groups in
            guard let day = groups.int(1), (1...31).contains(day) else { return nil }
            return date(.dayOfMonth(day))
        },
    ]
}
