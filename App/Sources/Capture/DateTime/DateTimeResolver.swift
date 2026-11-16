import Foundation

/// 적은 날과 시각을 실제 날짜로 푼다. "지금"과 달력(시간대 포함)은 밖에서 받는다.
///
/// 규칙:
/// - 날을 적지 않은 시각은 다가오는 그 시각이다. 오늘 지났으면 내일.
/// - 오전·오후를 적지 않은 1~12시는 후보(1~5시는 오후, 6~11시는 오전과 오후, 12시는 정오와 자정) 가운데
///   오늘 남은 가장 이른 것이다. 오늘 남은 것이 없으면 내일의 첫 후보. 다른 날의 시각이면 1~6시는 오후, 7~11시는 오전.
/// - 날만 적으면 오전 9시다.
/// - 요일, `11/20`, `20일`처럼 해나 주를 적지 않은 날은 다가오는 그날이다(오늘이 그날인데 시각이 지났으면 다음 것).
/// - 지난 때로 읽히는 것은 날을 분명히 적었을 때뿐이다(`오늘 오전 9시`를 오후에, `2020-01-01`).
nonisolated struct DateTimeResolver {
    typealias Assumptions = DateTimeExpression.Assumptions

    /// 한 시점: 날과 시각(둘 중 하나는 있다) 또는 지금부터 얼마 뒤.
    struct Point: Hashable {
        var date: DateSpec?
        var time: TimeSpec?
        var fromNow: TimeInterval?
    }

    struct Resolved: Hashable {
        var date: Date
        var assumptions: Assumptions
    }

    /// 날만 적었을 때의 시각.
    static let defaultHour = 9

    let now: Date
    let calendar: Calendar

    private var today: Date { calendar.startOfDay(for: now) }

    // MARK: - 한 시점

    func resolve(_ point: Point) -> Resolved? {
        if let interval = point.fromNow {
            return Resolved(date: now.addingTimeInterval(interval), assumptions: [])
        }
        guard let dateSpec = point.date else {
            return point.time.flatMap(upcoming)
        }
        guard let plan = days(for: dateSpec) else { return nil }
        for day in plan.days {
            var assumptions = plan.assumptions
            let resolved: Date?
            if let time = point.time {
                if let hour = time.definiteHour {
                    resolved = date(on: day, hour: hour, minute: time.minute)
                } else {
                    assumptions.insert(.meridiem)
                    if day == today {
                        let candidates = time.bareCandidates.compactMap { date(on: day, hour: $0, minute: time.minute) }
                        if let next = candidates.filter({ $0 > now }).min() {
                            resolved = next
                        } else if plan.isRolling {
                            continue
                        } else {
                            resolved = candidates.max()
                        }
                    } else {
                        resolved = date(on: day, hour: time.bareDefault, minute: time.minute)
                    }
                }
            } else {
                assumptions.insert(.timeOfDay)
                resolved = date(on: day, hour: Self.defaultHour, minute: 0)
            }
            guard let resolved else { continue }
            if resolved <= now {
                if plan.isRolling { continue }
                assumptions.insert(.past)
            }
            return Resolved(date: resolved, assumptions: assumptions)
        }
        return nil
    }

    /// 날을 적지 않은 시각: 다가오는 그 시각.
    private func upcoming(_ time: TimeSpec) -> Resolved? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        if let hour = time.definiteHour {
            // 밤 1시처럼 자정을 넘긴 시각도 다가오는 그 시각으로 읽는다.
            let clock = hour % 24
            let candidates = [today, tomorrow].compactMap { date(on: $0, hour: clock, minute: time.minute) }
            return candidates.first { $0 > now }.map { Resolved(date: $0, assumptions: []) }
        }
        let todays = time.bareCandidates.compactMap { date(on: today, hour: $0, minute: time.minute) }
        let next = todays.filter { $0 > now }.min()
            ?? time.bareCandidates.first.flatMap { date(on: tomorrow, hour: $0, minute: time.minute) }
        return next.map { Resolved(date: $0, assumptions: .meridiem) }
    }

    // MARK: - 범위의 끝과 시작

    /// 범위의 끝. 끝에 날이 없으면 시작과 같은 날에서 시작보다 뒤인 가장 이른 시각이다.
    /// 시작에 붙은 오전·오후는 끝으로 이어진다(`오후 2~4시`). 그렇게 읽은 끝이 시작보다 앞이면 열두 시간 뒤다(`오전 11시~1시`).
    func resolveEnd(_ end: Point, after start: Resolved, startPoint: Point) -> Resolved? {
        let fromStart = DateTimeResolver(now: start.date, calendar: calendar)
        guard end.fromNow == nil, end.date == nil, let time = end.time else {
            // 끝에 날이 있으면 시작을 "지금"으로 두고 읽는다(시작보다 뒤의 그날).
            if end.time == nil, let day = end.date.flatMap({ fromStart.days(for: $0)?.days.first }) {
                // 날만 적은 끝은 시작과 같은 시각이다.
                let clock = calendar.dateComponents([.hour, .minute], from: start.date)
                return date(on: day, hour: clock.hour ?? Self.defaultHour, minute: clock.minute ?? 0)
                    .map { Resolved(date: $0, assumptions: []) }
            }
            return end.fromNow == nil ? fromStart.resolve(end) : resolve(end)
        }
        let day = calendar.startOfDay(for: start.date)
        var assumptions: Assumptions = []
        let hours: [Int]
        if let hour = time.definiteHour {
            hours = [hour, hour + 24]
        } else if let inherited = (startPoint.time?.part ?? startPoint.time?.trailingPart)?.hour24(time.hour) {
            hours = [inherited, inherited + 12, inherited + 24]
        } else {
            assumptions.insert(.meridiem)
            hours = [time.hour, time.hour + 12, time.hour + 24]
        }
        return hours.lazy
            .compactMap { date(on: day, hour: $0, minute: time.minute) }
            .first { $0 > start.date }
            .map { Resolved(date: $0, assumptions: assumptions) }
    }

    /// 오전·오후가 끝에만 붙은 범위의 시작(`3~5pm`, `9시~오후 5시`): 끝과 같은 날에서 끝보다 앞인 가장 늦은 후보.
    func resolveStart(_ time: TimeSpec, before end: Date) -> Resolved? {
        let day = calendar.startOfDay(for: end)
        return [time.hour, time.hour + 12]
            .compactMap { date(on: day, hour: $0 % 24, minute: time.minute) }
            .filter { $0 < end }
            .max()
            .map { Resolved(date: $0, assumptions: []) }
    }

    // MARK: - 날

    private struct DayPlan {
        /// 이른 것부터. 앞의 날이 이미 지났으면 다음 날을 쓴다(`isRolling`일 때).
        var days: [Date]
        var isRolling: Bool
        var assumptions: Assumptions
    }

    private func days(for spec: DateSpec) -> DayPlan? {
        func adding(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }
        let weekday = calendar.component(.weekday, from: today) - 1

        switch spec {
        case .offsetDays(let offset):
            return adding(offset).map { DayPlan(days: [$0], isRolling: false, assumptions: []) }
        case .weekday(let index, .upcoming):
            let ahead = (index - weekday + 7) % 7
            return DayPlan(days: [ahead, ahead + 7].compactMap(adding), isRolling: true, assumptions: [])
        case .weekday(let index, .weeksAhead(let weeks)):
            // 한 주는 월요일에 시작한다.
            let sinceMonday = (weekday + 6) % 7
            return adding(weeks * 7 + (index + 6) % 7 - sinceMonday)
                .map { DayPlan(days: [$0], isRolling: false, assumptions: []) }
        case .monthDay(let month, let day, let year?, _):
            return validDate(year: year, month: month, day: day)
                .map { DayPlan(days: [$0], isRolling: false, assumptions: []) }
        case .monthDay(let month, let day, nil, let loose):
            let year = calendar.component(.year, from: today)
            // 2월 29일은 다음 윤년까지 본다.
            let candidates = (year...(year + 8))
                .compactMap { validDate(year: $0, month: month, day: day) }
                .filter { $0 >= today }
                .prefix(2)
            guard !candidates.isEmpty else { return nil }
            return DayPlan(days: Array(candidates), isRolling: true, assumptions: loose ? .looseDate : [])
        case .dayOfMonth(let day):
            let parts = calendar.dateComponents([.year, .month], from: today)
            guard let year = parts.year, let month = parts.month else { return nil }
            let candidates = (0..<14)
                .compactMap { offset in
                    validDate(year: year + (month - 1 + offset) / 12, month: (month - 1 + offset) % 12 + 1, day: day)
                }
                .filter { $0 >= today }
                .prefix(2)
            guard !candidates.isEmpty else { return nil }
            return DayPlan(days: Array(candidates), isRolling: true, assumptions: .looseDate)
        }
    }

    /// 달력에 없는 날(2월 30일, 13월)은 `nil`.
    private func validDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? date : nil
    }

    /// 그날의 시각. 24시 이상은 다음 날로 넘어간다.
    private func date(on day: Date, hour: Int, minute: Int) -> Date? {
        guard hour < 24 else {
            return calendar.date(byAdding: .day, value: hour / 24, to: day)
                .flatMap { date(on: $0, hour: hour % 24, minute: minute) }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
