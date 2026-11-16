import Foundation

/// 한국어와 영어가 섞인 글에서 날짜와 시간 표현을 읽는다. 규칙만 쓰고 네트워크나 모델을 쓰지 않는다.
///
/// 읽는 것:
/// - 시각: `3시`, `오후 3시`, `오전 10시 반`, `3시 30분`, `15:00`, `3pm`, `3:30 PM`, `PM 3`, `저녁 7시`, `아침 9시`,
///   `밤 11시`, `새벽 2시`, `정오`, `자정`, `noon`, `midnight`, `7시 저녁`(뒤따르는 말로 때를 안다)
/// - 날: `오늘`, `내일`, `모레`, `글피`, `today`, `tomorrow`, `금요일`, `이번 주 금요일`, `다음 주 월요일`, `fri`, `next mon`,
///   `11/20`, `11월 20일`, `20일`, `2026-11-20`, `3일 뒤`, `2주 후`, `in 3 days`
/// - 지금부터: `30분 뒤`, `2시간 후`, `1시간 반 뒤`, `in 2 hours`
/// - 범위: `3시~5시`, `3-5시`, `15:00-16:30`, `오후 2시 ~ 4시`, `오후 2~4시`, `2시부터 4시까지`, `3~5pm`, `11/20~11/22`.
///   리마인더는 시작에 걸리고 끝은 결과에 남는다.
///
/// 날과 시각은 날이 앞에 올 때만 하나로 읽는다(`내일 3시`). 표현이 여럿이면 맨 앞의 것 하나만 읽는다.
///
/// 읽지 않는 것(일부러):
/// - 시각 없는 `오늘`, `today`(리마인더로 뜻이 없다). 시각이나 범위 없이 적은 `11.20`, `sun`, `sat`(소수, 보통 낱말과 가려지지 않는다)
/// - 분수로 읽힐 말이 뒤따르는 `1/2 완료`, 기간과 차례(`3시간`, `20일간`, `3일째`, `2일 전`), 지난 때를 가리키는 말(`어제`, `3일 전`)
/// - 단위 없는 수(`3`, `3-5개`), 시각이 날보다 앞에 오는 꼴(`3시 내일`), `주말`, `월말`, `다음 달`, `오전`만 적은 글,
///   영어 달 이름(`Nov 20`), `3시 15분 전`, `반나절`, 되풀이(`매주 금요일`)
nonisolated enum DateTimeParser {
    static func firstExpression(in text: String, now: Date, calendar: Calendar) -> DateTimeExpression? {
        let resolver = DateTimeResolver(now: now, calendar: calendar)
        return candidates(in: text)
            .sorted { $0.range.location < $1.range.location }
            .lazy
            .compactMap { resolve($0, with: resolver) }
            .first
    }

    // MARK: - 시점과 범위로 잇기

    private typealias Point = DateTimeResolver.Point

    private struct Located {
        var point: Point
        var range: NSRange
        var requirement: DateTimePiece.Requirement = .none
        /// 수만 적은 범위의 시작(`3-5시`의 `3-`). 이음표까지 차지하고 있어 바로 다음 시점과 이어진다.
        var isBareRangeStart = false
    }

    private struct Candidate {
        var start: Located
        var end: Located?
        var range: NSRange
    }

    private static let connector = regex(#"^\s*(?:~|-|–|—|〜|부터|에서|[tT][oO])\s*$"#)
    private static let dateTimeGap = regex(#"^\s*(?:,\s*|에\s+)?$"#)
    private static let untilSuffix = regex(#"^\s*까지"#)
    private static let bareRangeStart = regex(
        #"(?:(오전|오후|아침|낮|점심|저녁|밤|새벽|AM|PM)\s*)?(?<![\d.:/])(\d{1,2})\s*(?:~|-|–|—|〜|부터|에서)\s*$"#
    )

    private static func candidates(in text: String) -> [Candidate] {
        let source = text as NSString
        let points = withBareRangeStarts(points(from: DateTimeLexer.pieces(in: text), source: source), source: source)

        var result: [Candidate] = []
        var index = 0
        while index < points.count {
            let start = points[index]
            if index + 1 < points.count, connects(start, points[index + 1], source: source) {
                let end = points[index + 1]
                var range = NSUnionRange(start.range, end.range)
                // "2시부터 4시까지"의 "까지"도 표현에 넣는다.
                let rest = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
                if let suffix = untilSuffix.firstMatch(in: text, range: rest) {
                    range = NSUnionRange(range, suffix.range)
                }
                result.append(Candidate(start: start, end: end, range: range))
                index += 2
                continue
            }
            if isReadableAlone(start) {
                result.append(Candidate(start: start, end: nil, range: start.range))
            }
            index += 1
        }
        return result
    }

    /// 조각을 시점으로 묶는다: 날 바로 뒤에 시각이 오면 한 시점이다.
    private static func points(from pieces: [DateTimePiece], source: NSString) -> [Located] {
        var points: [Located] = []
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            index += 1
            switch piece.kind {
            case .fromNow(let interval):
                points.append(Located(point: Point(fromNow: interval), range: piece.range))
            case .time(let time):
                points.append(Located(point: Point(time: time), range: piece.range))
            case .date(let date):
                var located = Located(point: Point(date: date), range: piece.range, requirement: piece.requirement)
                if index < pieces.count, case .time(let time) = pieces[index].kind,
                   matches(dateTimeGap, between: piece.range, and: pieces[index].range, source: source) {
                    located.point.time = time
                    located.range = NSUnionRange(piece.range, pieces[index].range)
                    index += 1
                }
                points.append(located)
            }
        }
        return points
    }

    /// 시각 앞에 "수와 이음표"가 붙어 있으면(`3-5시`, `오후 2~4시`) 그 수를 범위의 시작으로 끼워 넣는다.
    /// 이음표 뒤에 단위가 붙은 시각이 있을 때만이라서 `3-5개` 같은 글은 읽지 않는다.
    private static func withBareRangeStarts(_ points: [Located], source: NSString) -> [Located] {
        var result: [Located] = []
        for point in points {
            defer { result.append(point) }
            guard point.point.time != nil, point.point.date == nil else { continue }
            let floor = result.last.map { NSMaxRange($0.range) } ?? 0
            let before = NSRange(location: floor, length: point.range.location - floor)
            guard before.length > 0,
                  let match = bareRangeStart.firstMatch(in: source as String, range: before),
                  let hour = Int(source.substring(with: match.range(at: 2))), (0...24).contains(hour)
            else { continue }
            let partRange = match.range(at: 1)
            let part = partRange.location == NSNotFound
                ? nil : DayPart(word: source.substring(with: partRange))
            if let part, part.hour24(hour) == nil { continue }
            var start = Located(
                point: Point(time: TimeSpec(hour: hour, minute: 0, part: part)),
                range: match.range, isBareRangeStart: true
            )
            // 그 앞에 날만 적은 시점이 붙어 있으면 그 날의 범위다(`내일 3-5시`).
            if let previous = result.last, previous.point.time == nil, previous.point.fromNow == nil,
               matches(dateTimeGap, between: previous.range, and: match.range, source: source) {
                start.point.date = previous.point.date
                start.range = NSUnionRange(previous.range, match.range)
                result.removeLast()
            }
            result.append(start)
        }
        return result
    }

    private static func connects(_ start: Located, _ end: Located, source: NSString) -> Bool {
        guard start.point.fromNow == nil, end.point.fromNow == nil else { return false }
        if start.isBareRangeStart { return NSMaxRange(start.range) == end.range.location }
        return matches(connector, between: start.range, and: end.range, source: source)
    }

    /// 혼자서 읽을 수 있는 시점인지. 시각 없는 `오늘`, 시각 없는 `11.20`은 아니다. 수만 적은 범위의 시작도 아니다.
    private static func isReadableAlone(_ located: Located) -> Bool {
        guard !located.isBareRangeStart else { return false }
        return located.requirement == .none || located.point.time != nil
    }

    // MARK: - 날짜로 풀기

    private static func resolve(_ candidate: Candidate, with resolver: DateTimeResolver) -> DateTimeExpression? {
        let startPoint = candidate.start.point
        guard let endPoint = candidate.end?.point else {
            return resolver.resolve(startPoint).map {
                DateTimeExpression(start: $0.date, end: nil, range: candidate.range, assumptions: $0.assumptions)
            }
        }

        // 오전·오후가 끝에만 붙었으면(`3~5pm`) 끝을 먼저 읽고 시작을 그 앞에 맞춘다.
        if let startTime = startPoint.time, startTime.isBare, endPoint.date == nil,
           let endTime = endPoint.time, endTime.part != nil,
           let end = resolver.resolve(DateTimeResolver.Point(date: startPoint.date, time: endTime)),
           let start = resolver.resolveStart(startTime, before: end.date) {
            return DateTimeExpression(
                start: start.date, end: end.date, range: candidate.range,
                assumptions: start.assumptions.union(end.assumptions)
            )
        }

        guard let start = resolver.resolve(startPoint) else { return nil }
        let end = resolver.resolveEnd(endPoint, after: start, startPoint: startPoint)
        return DateTimeExpression(
            start: start.date,
            end: end.flatMap { $0.date > start.date ? $0.date : nil },
            range: candidate.range,
            assumptions: start.assumptions.union(end?.assumptions ?? [])
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

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("날짜 무늬가 잘못됐습니다: \(pattern): \(error)")
        }
    }
}
