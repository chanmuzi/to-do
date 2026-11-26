import Foundation

/// 한국어와 영어가 섞인 글에서 날짜와 시간 표현을 읽는다. 규칙만 쓰고 네트워크나 모델을 쓰지 않는다.
/// 읽는 꼴과 읽지 않는 꼴의 표는 `docs/spec/07a-datetime.md`, 경우를 적은 테스트는 `DateTimeParserTests`에 있다.
///
/// 차례: 글을 고른다(`NormalizedText`) → 조각을 찾는다(`DateTimeLexer`) → 조각을 시점과 범위로 잇는다(여기) →
/// 날짜로 푼다(`DateTimeResolver`). "지금", 달력, 시간대는 밖에서 받는다.
///
/// 잇는 규칙:
/// - 날과 시각이 붙어 있으면 어느 쪽이 먼저든 한 시점이다(`내일 3시`, `3시 내일`, `10am friday`).
///   사이에 `에`, `은`, `는`, `,`, `at`, `@`, 요일 덧말(`11/20(금) 3시`, `11/20 금요일 3시`)이 있어도 된다.
/// - 날 바로 뒤의 때를 가리키는 말은 그 날의 것이다(`내일 저녁 약속`).
/// - 맨 앞 표현이 날만 적은 것이고 글의 다른 곳에 시각이 꼭 하나 있으면 둘을 합친다(`내일 회의 3시`).
///   글에 표현이 시각 하나와 날 하나뿐일 때는 시각이 앞이어도 합친다(`3시 회의 내일`). 이때 차지한 글자는 두 곳이다.
/// - 표현이 여럿이면 맨 앞의 것 하나만 읽는다.
public nonisolated enum DateTimeParser {
    public static func firstExpression(in text: String, now: Date, calendar: Calendar) -> DateTimeExpression? {
        let normalized = NormalizedText(text)
        let resolver = DateTimeResolver(now: now, calendar: calendar)
        for candidate in candidates(in: normalized.text) {
            guard let outcome = resolve(candidate, with: resolver) else { continue }
            return DateTimeExpression(
                start: outcome.start, end: outcome.end,
                ranges: candidate.ranges.map(normalized.originalRange),
                assumptions: outcome.assumptions,
                isDateOnly: candidate.start.point.time == nil && candidate.start.point.part == nil
                    && candidate.start.point.fromNow == nil && candidate.end?.point.time == nil
                    && candidate.end?.point.part == nil
            )
        }
        return nil
    }

    // MARK: - 시점과 범위로 잇기

    private typealias Point = DateTimeResolver.Point

    private struct Located {
        var point: Point
        var range: NSRange
        var requirement: DateTimePiece.Requirement = .none
        /// 수만 적은 범위의 시작(`3-5시`의 `3-`). 이음표까지 차지하고 있어 바로 다음 시점과 이어진다.
        var isBareRangeStart = false
        /// 한 덩어리로 적은 날의 범위(`20~22일`)의 끝.
        var spanEnd: DateSpec?

        var isDateOnly: Bool {
            guard let date = point.date, date != .void else { return false }
            return point.time == nil && point.fromNow == nil && spanEnd == nil
        }

        var isTimeOnly: Bool {
            point.time != nil && point.date == nil && point.fromNow == nil && !point.isDaily
        }
    }

    private struct Candidate {
        var start: Located
        var end: Located?
        var ranges: [NSRange]
    }

    private static let connector = regex(#"^\s*(?:~|-|부터|에서|[tT][oO])\s*$"#)
    private static let fromPrefix = regex(#"(?i)\bfrom\s+$"#)
    private static let toConnector = regex(#"(?i)^\s*to\s*"#)
    private static let blank = regex(#"^\s*$"#)
    /// 날 뒤에 시각이 올 때 사이에 있어도 되는 말.
    private static let dateTimeGap = regex(#"^\s*(?:(?:,|에는|에|은|는|엔|[aA][tT]|@)\s*)?$"#)
    /// 시각 뒤에 날이 올 때 사이에 있어도 되는 말.
    private static let timeDateGap = regex(#"^\s*(?:(?:,|에|[oO][nN])\s*)?$"#)
    private static let untilSuffix = regex(#"^\s*까지"#)
    private static let bareRangeStart = regex(
        #"(?:(오전|오후|아침|낮|점심|저녁|밤|새벽|AM|PM)\s*)?(?<![\d.:/A-Za-z])(\d{1,2})\s*(?:~|-|부터|에서|[tT][oO]\b)\s*$"#
    )
    /// 오전, 오후가 붙은 시각 뒤에 수만 적은 범위의 끝(`2pm-4`).
    private static let bareRangeEnd = regex(#"^\s*(?:~|-|[tT][oO]\s)\s*(\d{1,2})(?![\d:.,/%가-힣A-Za-z])"#)

    private static func candidates(in text: String) -> [Candidate] {
        let source = text as NSString
        let points = withBareRangeStarts(points(from: DateTimeLexer.pieces(in: text), source: source), source: source)

        var result: [Candidate] = []
        var index = 0
        while index < points.count {
            let start = points[index]
            index += 1
            if let spanEnd = start.spanEnd {
                let end = Located(point: Point(date: spanEnd), range: start.range)
                result.append(Candidate(start: start, end: end, ranges: [start.range]))
            } else if index < points.count, connects(start, points[index], source: source) {
                let end = points[index]
                index += 1
                var range = rangeIncludingFrom(start, end, source: source)
                // "2시부터 4시까지"의 "까지"도 표현에 넣는다.
                let rest = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
                if let suffix = untilSuffix.firstMatch(in: text, range: rest) {
                    range = NSUnionRange(range, suffix.range)
                }
                result.append(Candidate(start: start, end: end, ranges: [range]))
            } else if let end = bareEnd(after: start, source: source) {
                result.append(Candidate(start: start, end: end, ranges: [rangeIncludingFrom(start, end, source: source)]))
            } else if !start.isBareRangeStart {
                result.append(Candidate(start: start, end: nil, ranges: [start.range]))
            }
        }
        return joiningSeparatedDateAndTime(result).filter(isReadable)
    }

    private static func rangeIncludingFrom(_ start: Located, _ end: Located, source: NSString) -> NSRange {
        let range = NSUnionRange(start.range, end.range)
        let tail = NSRange(location: NSMaxRange(start.range), length: NSMaxRange(range) - NSMaxRange(start.range))
        let hasTo = start.isBareRangeStart
            ? source.substring(with: start.range).trimmingCharacters(in: .whitespaces).lowercased().hasSuffix("to")
            : toConnector.firstMatch(in: source as String, range: tail) != nil
        guard hasTo,
              let prefix = fromPrefix.firstMatch(in: source as String, range: NSRange(location: 0, length: range.location))
        else { return range }
        return NSUnionRange(prefix.range, range)
    }

    /// 조각을 시점으로 묶는다: 붙어 있는 날과 시각은 한 시점이다.
    private static func points(from pieces: [DateTimePiece], source: NSString) -> [Located] {
        var points: [Located] = []
        var index = 0
        func isNext(_ regex: NSRegularExpression, after range: NSRange) -> Bool {
            index < pieces.count && matches(regex, between: range, and: pieces[index].range, source: source)
        }
        /// 날 뒤의 요일 덧말을 표현에 넣는다: `(금)`, 요일이 아닌 날 뒤의 요일(`11/20 금요일`).
        func absorbWeekdayNotes(into located: inout Located, after spec: DateSpec) {
            if case .shortYearDate = spec { return }
            while isNext(blank, after: located.range) {
                switch pieces[index].kind {
                case .weekdayNote: break
                case .date(.weekday(_, .upcoming)):
                    if case .weekday = spec { return }
                default: return
                }
                located.range = NSUnionRange(located.range, pieces[index].range)
                index += 1
            }
        }

        while index < pieces.count {
            let piece = pieces[index]
            index += 1
            switch piece.kind {
            case .dayPart, .weekdayNote:
                continue
            case .fromNow(let interval):
                points.append(Located(point: Point(fromNow: interval), range: piece.range))
            case .dateTime(let date, let time):
                points.append(Located(point: Point(date: date, time: time), range: piece.range))
            case .dateSpan(let first, let last):
                points.append(Located(point: Point(date: first), range: piece.range, spanEnd: last))
            case .daily:
                // `매일`은 바로 뒤의 시각과 함께일 때만 뜻이 있다.
                guard isNext(blank, after: piece.range), case .time(let time) = pieces[index].kind else { continue }
                points.append(Located(
                    point: Point(time: time, isDaily: true), range: NSUnionRange(piece.range, pieces[index].range)
                ))
                index += 1
            case .date(.void):
                // 지난 때와 되풀이는 붙어 있는 날과 시각을 함께 가져간다. 남은 조각이 다른 뜻으로 읽히지 않게.
                var located = Located(point: Point(date: .void), range: piece.range)
                while isNext(blank, after: located.range) {
                    located.range = NSUnionRange(located.range, pieces[index].range)
                    index += 1
                }
                points.append(located)
            case .date(var spec):
                var located = Located(
                    point: Point(date: spec, part: piece.impliedPart), range: piece.range, requirement: piece.requirement
                )
                // `2주 뒤 금요일`: 몇 주 뒤의 그 요일이다.
                if case .offsetDays(let days) = spec, days >= 7, days % 7 == 0, isNext(blank, after: piece.range),
                   case .date(.weekday(let weekday, .upcoming)) = pieces[index].kind {
                    spec = .weekday(weekday, .weeksAhead(days / 7))
                    located.point.date = spec
                    located.range = NSUnionRange(located.range, pieces[index].range)
                    index += 1
                }
                absorbWeekdayNotes(into: &located, after: spec)
                if isNext(blank, after: located.range), case .dayPart(let part) = pieces[index].kind {
                    located.point.part = part
                    located.range = NSUnionRange(located.range, pieces[index].range)
                    index += 1
                }
                if isNext(dateTimeGap, after: located.range), case .time(let time) = pieces[index].kind {
                    located.point.time = time.applying(located.point.part)
                    located.range = NSUnionRange(located.range, pieces[index].range)
                    index += 1
                }
                points.append(located)
            case .time(let time):
                var located = Located(point: Point(time: time), range: piece.range, requirement: piece.requirement)
                // 시각 뒤의 날(`3시 내일`). 그 날이 제 시각을 따로 달고 있으면(`3시, 내일 5시`) 잇지 않는다.
                if isNext(timeDateGap, after: piece.range), case .date(let spec) = pieces[index].kind, spec != .void,
                   !hasOwnTime(pieces, at: index, source: source) {
                    located.point.date = spec
                    located.point.time = time.applying(pieces[index].impliedPart)
                    located.range = NSUnionRange(located.range, pieces[index].range)
                    located.requirement = .none
                    index += 1
                    absorbWeekdayNotes(into: &located, after: spec)
                }
                points.append(located)
            }
        }
        return points
    }

    /// `index`의 날 조각 바로 뒤에 그 날의 시각이 붙어 있는지.
    private static func hasOwnTime(_ pieces: [DateTimePiece], at index: Int, source: NSString) -> Bool {
        guard index + 1 < pieces.count, case .time = pieces[index + 1].kind else { return false }
        return matches(dateTimeGap, between: pieces[index].range, and: pieces[index + 1].range, source: source)
    }

    /// 시각 앞에 "수와 이음표"가 붙어 있으면(`3-5시`, `오후 2~4시`) 그 수를 범위의 시작으로 끼워 넣는다.
    /// 이음표 뒤에 단위가 붙은 시각이 있을 때만이라서 `3-5개` 같은 글은 읽지 않는다. 글자나 수에 붙은 수(`B1-3시`)도 아니다.
    private static func withBareRangeStarts(_ points: [Located], source: NSString) -> [Located] {
        var result: [Located] = []
        for point in points {
            defer { result.append(point) }
            guard point.isTimeOnly else { continue }
            let floor = result.last.map { NSMaxRange($0.range) } ?? 0
            let before = NSRange(location: floor, length: point.range.location - floor)
            guard before.length > 0,
                  let match = bareRangeStart.firstMatch(in: source as String, range: before),
                  let hour = Int(source.substring(with: match.range(at: 2)))
            else { continue }
            let partRange = match.range(at: 1)
            let part = partRange.location == NSNotFound ? nil : DayPart(word: source.substring(with: partRange))
            guard let time = DateTimeLexer.timeSpec(hour: hour, part: part) else { continue }
            var start = Located(point: Point(time: time), range: match.range, isBareRangeStart: true)
            // 그 앞에 날만 적은 시점이 붙어 있으면 그 날의 범위다(`내일 3-5시`, `내일 오후 2~4시`).
            if let previous = result.last, previous.point.date != nil, previous.point.time == nil,
               previous.spanEnd == nil, matches(dateTimeGap, between: previous.range, and: match.range, source: source) {
                start.point.date = previous.point.date
                start.point.time = time.applying(previous.point.part)
                start.range = NSUnionRange(previous.range, match.range)
                result.removeLast()
            }
            result.append(start)
        }
        return result
    }

    private static func connects(_ start: Located, _ end: Located, source: NSString) -> Bool {
        guard start.point.fromNow == nil, end.point.fromNow == nil, end.spanEnd == nil,
              !start.point.isDaily, !end.point.isDaily else { return false }
        if start.isBareRangeStart { return NSMaxRange(start.range) == end.range.location }
        // 끝에 날이 없으면 시작에 시각이 있어야 범위다(`내일~3시`는 범위가 아니다).
        guard end.point.date != nil || start.point.time != nil else { return false }
        return matches(connector, between: start.range, and: end.range, source: source)
    }

    /// `2pm-4`의 `-4`: 오전, 오후를 적은 시각 뒤에 이음표와 수만 있을 때의 끝.
    private static func bareEnd(after start: Located, source: NSString) -> Located? {
        guard start.point.time?.part != nil, start.point.fromNow == nil, !start.point.isDaily else { return nil }
        let rest = NSRange(location: NSMaxRange(start.range), length: source.length - NSMaxRange(start.range))
        guard let match = bareRangeEnd.firstMatch(in: source as String, range: rest),
              let hour = Int(source.substring(with: match.range(at: 1))), (1...12).contains(hour),
              let time = DateTimeLexer.timeSpec(hour: hour) else { return nil }
        return Located(point: Point(time: time), range: match.range)
    }

    /// 떨어뜨려 적은 날과 시각을 합친다(`내일 회의 3시`, `금요일 팀 회식 7시`).
    private static func joiningSeparatedDateAndTime(_ candidates: [Candidate]) -> [Candidate] {
        guard let first = candidates.first else { return candidates }
        // 소수나 보통 낱말과 가려지지 않는 날(`3.2`, `sun`)은 떨어진 시각만으로는 날이 되지 않는다.
        func isDateOnly(_ candidate: Candidate) -> Bool {
            candidate.end == nil && candidate.start.isDateOnly && candidate.start.requirement != .needsCompany
        }
        func isTimeOnly(_ candidate: Candidate) -> Bool {
            candidate.start.isTimeOnly && (candidate.end.map { $0.isTimeOnly } ?? true)
        }
        func joined(date: Candidate, time: Candidate) -> Candidate {
            var merged = time
            merged.start.point.date = date.start.point.date
            merged.start.point.time = time.start.point.time?.applying(date.start.point.part)
            merged.start.requirement = .none
            merged.ranges = (date.ranges + time.ranges).sorted { $0.location < $1.location }
            return merged
        }

        if isDateOnly(first) {
            let times = candidates.indices.dropFirst().filter { isTimeOnly(candidates[$0]) }
            guard times.count == 1, let index = times.first else { return candidates }
            var rest = candidates
            let time = rest.remove(at: index)
            rest[0] = joined(date: first, time: time)
            return rest
        }
        if candidates.count == 2, isTimeOnly(first), isDateOnly(candidates[1]) {
            return [joined(date: candidates[1], time: first)]
        }
        return candidates
    }

    /// 혼자서 읽을 수 있는 표현인지. 시각 없는 `오늘`, 시각도 범위도 없는 `11.20`, 날 없는 `at 10`은 아니다.
    private static func isReadable(_ candidate: Candidate) -> Bool {
        let point = candidate.start.point
        switch candidate.start.requirement {
        case .none: return true
        case .needsTime: return point.time != nil || point.part != nil
        case .needsCompany: return point.time != nil || candidate.end != nil
        case .needsDate: return point.date != nil
        }
    }

    // MARK: - 날짜로 풀기

    private static func resolve(_ candidate: Candidate, with resolver: DateTimeResolver) -> DateTimeResolver.Outcome? {
        guard let end = candidate.end else {
            return resolver.resolve(candidate.start.point, isAlone: true)
        }
        return resolver.resolveRange(
            start: candidate.start.point, end: end.point, requiresEnd: candidate.start.spanEnd != nil
        )
    }

    // MARK: - 도우미

    private static func matches(
        _ regex: NSRegularExpression, between first: NSRange, and second: NSRange, source: NSString
    ) -> Bool {
        let gap = NSRange(location: NSMaxRange(first), length: second.location - NSMaxRange(first))
        guard gap.length >= 0 else { return false }
        let text = source.substring(with: gap)
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression { DateTimeLexer.regex(pattern) }
}
