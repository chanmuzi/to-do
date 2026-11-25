import DateTime
import Foundation
import Observation

@MainActor @Observable
public final class ScheduleDateSelection {
    static let displayLocale = Locale(identifier: "ko_KR")

    let calendar: Calendar
    let now: Date
    public private(set) var week: Date
    var cursor: Date
    var monthCursor: Date?
    var month: Date
    public var choosingMonth = false
    var quickIndex: Int? = 0
    var input = ""

    init(selected: Date, now: Date, calendar: Calendar) {
        self.calendar = calendar
        self.now = now
        cursor = selected
        month = now
        week = Self.sunday(containing: now, calendar: calendar)
    }

    private static func sunday(containing date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: date), to: calendar.startOfDay(for: date))!
    }

    func day(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date)!
    }

    public func scrollWeeks(_ count: Int) {
        week = day(count * 7, from: week)
        month = week
        quickIndex = nil
    }

    func moveDay(_ count: Int) {
        cursor = day(count, from: cursor)
        if cursor < week || cursor >= day(28, from: week) {
            week = Self.sunday(containing: cursor, calendar: calendar)
            month = cursor
        }
        quickIndex = nil
    }

    func moveHeader(_ direction: Int) {
        if choosingMonth {
            month = calendar.date(byAdding: .year, value: direction, to: month)!
            monthCursor = nil
        }
        else {
            let first = calendar.dateInterval(of: .month, for: month)!.start
            showMonth(calendar.date(byAdding: .month, value: direction, to: first)!)
        }
    }

    func moveMonthCursor(_ offset: Int) {
        let initial = calendar.isDate(cursor, equalTo: month, toGranularity: .year) ? cursor : month
        let next = calendar.date(byAdding: .month, value: offset, to: monthCursor ?? initial)!
        month = next
        monthCursor = next
    }

    func showMonth(_ date: Date) {
        monthCursor = nil
        if !calendar.isDate(date, equalTo: cursor, toGranularity: .month) { cursor = date }
        month = date
        week = Self.sunday(containing: date, calendar: calendar)
        choosingMonth = false
    }

    func quickDay(_ index: Int) -> Date {
        if index < 2 { return day(index, from: now) }
        let weekday = calendar.component(.weekday, from: now)
        return day(7 - (weekday + 5) % 7, from: now)
    }

    func parse() -> DateTimeExpression? {
        DateTimeParser.firstExpression(in: input, now: now, calendar: calendar)
    }

    func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.displayLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
