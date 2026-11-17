import Foundation

/// 적은 날과 시각을 실제 날짜로 푼다. "지금"과 달력(시간대 포함)은 밖에서 받는다. 규칙의 전체 표는 spec 7a.
///
/// - 오전, 오후를 적지 않은 시각은 흔한 쪽으로 읽는다: 1~7시는 오후, 8~11시는 오전, 12시는 정오.
///   날을 적지 않았으면 그 시각이 오늘 아직 남았을 때 오늘, 지났으면 같은 시각의 내일이다. 날을 적었으면 그날의 그 시각이다.
/// - 24시간제나 오전, 오후를 적은 시각도 날을 적지 않았으면 다가오는 그 시각이다.
/// - 날만 적으면 오전 9시다. 때를 가리키는 말이 함께 있으면 `DateTimeDefaults`의 값이다.
/// - 요일, `11/20`, `20일`처럼 해나 주를 적지 않은 날은 오늘이거나 다가오는 그날이다. 오늘이 그날이면 언제나 오늘이고,
///   시각이 지났으면 다음 주나 다음 해로 넘기지 않고 지난 때(`.past`)로 알린다.
nonisolated struct DateTimeResolver {
    typealias Assumptions = DateTimeExpression.Assumptions

    /// 한 시점: 날, 시각, 때를 가리키는 말 가운데 적은 것. 또는 지금부터 얼마 뒤.
    struct Point: Hashable {
        var date: DateSpec?
        var time: TimeSpec?
        /// 시각 없이 날에 붙은 때를 가리키는 말(`내일 저녁`).
        var part: DayPart?
        var fromNow: TimeInterval?
        /// `매일`이 붙어 있었다.
        var isDaily = false
    }

    struct Outcome: Hashable {
        var start: Date
        var end: Date?
        var assumptions: Assumptions
    }

    /// 분수로도 읽히는 `M/D`(월이 일보다 작다)를 혼자 적었을 때, 다가오는 그날이 이보다 멀면 날짜로 보지 않는다(`9/10`).
    static let looseDateHorizonDays = 180

    let now: Date
    let calendar: Calendar

    private var today: Date { calendar.startOfDay(for: now) }

    // MARK: - 한 시점

    /// - Parameter isAlone: 시각도 범위도 없이 날만 적은 표현이다. 날짜가 아닐 수도 있는 꼴을 더 엄하게 가린다.
    func resolve(_ point: Point, isAlone: Bool) -> Outcome? {
        if let interval = point.fromNow {
            return Outcome(start: now.addingTimeInterval(interval), end: nil, assumptions: [])
        }
        var assumptions = notes(for: point)
        guard let spec = point.date else {
            guard let time = point.time, let upcoming = upcoming(time) else { return nil }
            return Outcome(start: upcoming.date, end: nil, assumptions: assumptions.union(upcoming.assumptions))
        }
        guard let plan = day(for: spec, isAlone: isAlone && point.time == nil) else { return nil }
        assumptions.formUnion(plan.assumptions)

        let resolved: Date?
        if let time = point.time {
            if time.isBare { assumptions.insert(.meridiem) }
            resolved = instant(on: plan.day, time, hour: time.definiteHour ?? time.preferredHour)
        } else {
            assumptions.insert(.timeOfDay)
            resolved = date(on: plan.day, hour: DateTimeDefaults.hour(for: point.part), minute: 0)
        }
        guard let resolved else { return nil }
        if resolved <= now { assumptions.insert(.past) }
        return Outcome(start: resolved, end: nil, assumptions: assumptions)
    }

    /// 날을 적지 않은 시각: 다가오는 그 시각.
    private func upcoming(_ time: TimeSpec) -> (date: Date, assumptions: Assumptions)? {
        // 밤 1시처럼 자정을 넘긴 시각도 다가오는 그 시각으로 읽는다.
        let hour = (time.definiteHour ?? time.preferredHour) % 24
        return (0...2).lazy
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .compactMap { instant(on: $0, time, hour: hour) }
            .first { $0 > now }
            .map { ($0, time.isBare ? .meridiem : []) }
    }

    /// 되풀이와 시간대처럼 시각을 바꾸지는 않지만 알려 둘 것.
    private func notes(for point: Point) -> Assumptions {
        var assumptions: Assumptions = point.isDaily ? .recurring : []
        if let zone = point.time?.zone, !isLocal(zone: zone) { assumptions.insert(.unknownTimeZone) }
        return assumptions
    }

    /// 적은 시간대가 지금 달력의 시간대와 같은 시각을 가리키는지.
    private func isLocal(zone: String) -> Bool {
        let local = calendar.timeZone.secondsFromGMT(for: now)
        if zone == "Z" { return local == 0 }
        if let sign = zone.first, sign == "+" || sign == "-" {
            let digits = zone.dropFirst().filter(\.isNumber)
            guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2))
            else { return false }
            return local == (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
        }
        return TimeZone(abbreviation: zone)?.secondsFromGMT(for: now) == local
    }

    // MARK: - 범위

    /// 범위. 한 날 안의 시각 범위는 양 끝이 서로 맞게 읽는다(`9-6시`는 09:00~18:00). 끝에 날이 있으면 끝은 제 날로 읽는다.
    /// - Parameter requiresEnd: 끝을 읽지 못하면 범위 전체를 읽지 않는다(`20~22일`).
    func resolveRange(start: Point, end: Point, requiresEnd: Bool = false) -> Outcome? {
        if let startTime = start.time, let endTime = end.time, end.date == nil,
           start.fromNow == nil, end.fromNow == nil {
            return clockRange(start: start, startTime, end: end, endTime)
        }
        guard var outcome = resolve(start, isAlone: false) else { return nil }
        let endDate = self.end(end, after: outcome.start)
        if requiresEnd, endDate == nil { return nil }
        outcome.end = endDate
        return outcome
    }

    /// 제 날을 가진 끝. 날만 적은 끝은 시작과 같은 시각이다. 해나 주를 적지 않은 날이 시작보다 앞이면 시작 뒤의 그날이다
    /// (`12/30~1/2`의 1월 2일은 다음 해).
    private func end(_ point: Point, after start: Date) -> Date? {
        guard point.date != nil, point.fromNow == nil else { return nil }
        for resolver in [self, DateTimeResolver(now: start, calendar: calendar)] {
            let resolved: Date?
            if point.time == nil, point.part == nil {
                let clock = calendar.dateComponents([.hour, .minute], from: start)
                resolved = point.date.flatMap { resolver.day(for: $0, isAlone: false) }.flatMap {
                    date(on: $0.day, hour: clock.hour ?? DateTimeDefaults.dateOnlyHour, minute: clock.minute ?? 0)
                }
            } else {
                resolved = resolver.resolve(point, isAlone: false)?.start
            }
            if let resolved, resolved > start { return resolved }
        }
        return nil
    }

    /// 한 날 안의 시각 범위(`3시~5시`, `9-6시`, `오후 2~4시`, `3~5pm`, `밤 11시~1시`).
    ///
    /// - 양쪽 다 오전, 오후가 없으면 시작은 흔한 쪽으로 읽고, 끝은 시작보다 뒤인 가장 이른 시각이다.
    /// - 한쪽에만 있으면 다른 쪽이 따라간다: 끝은 시작보다 뒤인 가장 이른 시각, 시작은 끝보다 앞인 가장 늦은 시각.
    /// - 같은 날에 시작보다 뒤로 읽을 길이 없을 때만 끝이 다음 날로 넘어간다.
    /// - 날을 적지 않았으면 끝이 아직 남은 가장 가까운 날이다. 시작이 이미 지났으면(진행 중) `.past`로 알린다.
    private func clockRange(start: Point, _ startTime: TimeSpec, end: Point, _ endTime: TimeSpec) -> Outcome? {
        var assumptions = notes(for: start).union(notes(for: end))
        let startMinutes: Int
        var endMinutes: Int
        let halfDay = 12 * 60
        func minutes(_ time: TimeSpec, hour: Int) -> Int { hour * 60 + time.minute - time.minutesBefore }

        switch (startTime.definiteHour, endTime.definiteHour) {
        case let (startHour?, endHour?):
            startMinutes = minutes(startTime, hour: startHour)
            endMinutes = minutes(endTime, hour: endHour)
            if endMinutes <= startMinutes { endMinutes += 2 * halfDay }
        case let (nil, endHour?):
            endMinutes = minutes(endTime, hour: endHour)
            let written = minutes(startTime, hour: startTime.hour % 12)
            startMinutes = [written + halfDay, written].first { $0 < endMinutes }
                ?? minutes(startTime, hour: startTime.preferredHour)
            if endMinutes <= startMinutes { endMinutes += 2 * halfDay }
        case let (startHour, nil):
            if startHour == nil || startTime.part == nil { assumptions.insert(.meridiem) }
            startMinutes = minutes(startTime, hour: startHour ?? startTime.preferredHour)
            let written = minutes(endTime, hour: endTime.hour % 12)
            endMinutes = [written, written + halfDay, written + 2 * halfDay, written + 3 * halfDay]
                .first { $0 > startMinutes } ?? written + 2 * halfDay
        }

        func instant(on day: Date, _ minutes: Int) -> Date? {
            minutes >= 0 ? date(on: day, hour: minutes / 60, minute: minutes % 60) : nil
        }

        let day: Date
        if let spec = start.date {
            guard let plan = self.day(for: spec, isAlone: false) else { return nil }
            assumptions.formUnion(plan.assumptions)
            day = plan.day
        } else {
            // 자정을 넘겨 적은 시작(밤 1시)은 어제에서 센 것일 수도 있다.
            let offsets = (startMinutes >= 2 * halfDay ? [-1] : []) + [0, 1]
            let days = offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            guard let chosen = days.first(where: { instant(on: $0, endMinutes).map { $0 > now } ?? false })
            else { return nil }
            day = chosen
        }
        guard let startDate = instant(on: day, startMinutes), let endDate = instant(on: day, endMinutes),
              endDate > startDate else { return nil }
        if startDate <= now { assumptions.insert(.past) }
        return Outcome(start: startDate, end: endDate, assumptions: assumptions)
    }

    // MARK: - 날

    private struct DayPlan {
        var day: Date
        var assumptions: Assumptions = []
    }

    private func day(for spec: DateSpec, isAlone: Bool) -> DayPlan? {
        func adding(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }
        let weekday = calendar.component(.weekday, from: today) - 1
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { return nil }
        /// 이번 달에서 `offset`달 뒤의 `day`일.
        func inMonth(_ offset: Int, day: Int) -> Date? {
            validDate(year: year + (month - 1 + offset) / 12, month: (month - 1 + offset) % 12 + 1, day: day)
        }

        switch spec {
        case .void:
            return nil
        case .offsetDays(let offset):
            return adding(offset).map { DayPlan(day: $0) }
        case .offsetMonths(let offset):
            return calendar.date(byAdding: .month, value: offset, to: today).map { DayPlan(day: $0) }
        case .weekday(let index, .upcoming):
            // 오늘이 그 요일이면 오늘이다.
            return adding((index - weekday + 7) % 7).map { DayPlan(day: $0) }
        case .weekday(let index, .weeksAhead(let weeks)):
            // 한 주는 월요일에 시작한다.
            let sinceMonday = (weekday + 6) % 7
            return adding(weeks * 7 + (index + 6) % 7 - sinceMonday).map { DayPlan(day: $0) }
        case .monthDay(let month, let day, .exact(let year)?, _):
            return validDate(year: year, month: month, day: day).map { DayPlan(day: $0) }
        case .monthDay(let month, let day, .fromNow(let offset)?, _):
            return validDate(year: year + offset, month: month, day: day).map { DayPlan(day: $0) }
        case .monthDay(let month, let day, nil, let loose):
            // 2월 29일은 다음 윤년까지 본다.
            guard let next = (year...(year + 8)).lazy
                .compactMap({ validDate(year: $0, month: month, day: day) })
                .first(where: { $0 >= today }) else { return nil }
            if loose, isAlone, month < day,
               let distance = calendar.dateComponents([.day], from: today, to: next).day,
               distance > Self.looseDateHorizonDays {
                return nil
            }
            return DayPlan(day: next, assumptions: loose ? .looseDate : [])
        case .monthOffsetDay(let months, let day):
            return inMonth(months, day: day).map { DayPlan(day: $0) }
        case .dayOfMonth(let day):
            return (0..<14).lazy.compactMap { inMonth($0, day: day) }.first { $0 >= today }
                .map { DayPlan(day: $0, assumptions: .looseDate) }
        case .comingDayThisMonth(let day):
            guard day >= dayNumber else { return nil }
            return inMonth(0, day: day).map { DayPlan(day: $0, assumptions: .looseDate) }
        }
    }

    /// 달력에 없는 날(2월 30일, 13월)은 `nil`.
    private func validDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? date : nil
    }

    /// 그날의 그 시각. `3시 5분 전`의 분을 뺀다.
    private func instant(on day: Date, _ time: TimeSpec, hour: Int) -> Date? {
        date(on: day, hour: hour, minute: time.minute)?.addingTimeInterval(TimeInterval(-time.minutesBefore * 60))
    }

    /// 그날의 시각. 24시 이상은 다음 날로 넘어간다. 서머타임으로 없는 시각은 그 뒤의 첫 시각이 된다(02:30은 03:00).
    private func date(on day: Date, hour: Int, minute: Int) -> Date? {
        guard hour < 24 else {
            return calendar.date(byAdding: .day, value: hour / 24, to: day)
                .flatMap { date(on: $0, hour: hour % 24, minute: minute) }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
