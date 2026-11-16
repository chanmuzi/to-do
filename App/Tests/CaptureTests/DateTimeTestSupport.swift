import Foundation
import Testing
@testable import Capture

/// 날짜와 시간 읽기 표의 한 줄: 글, 지금, 알아들은 글자(여러 곳이면 차례대로), 시작, 끝, 꼭 있어야 하는 짐작.
nonisolated struct ParseCase: Sendable, CustomTestStringConvertible {
    typealias Assumptions = DateTimeExpression.Assumptions

    var text: String
    var now: Date
    /// 알아들은 글자. `nil`이면 견주지 않는다.
    var matches: [String]?
    var start: Date
    var end: Date?
    /// 결과에 들어 있어야 하는 짐작.
    var flags: Assumptions = []
    /// 결과에 없어야 하는 짐작.
    var absent: Assumptions = []
    var calendar: Calendar = TestClock.calendar

    var testDescription: String { "\(text) @\(now.formatted(.iso8601))" }

    /// 기본 "지금": 2026년 11월 16일 월요일 10:00(서울).
    static let morning = at(11, 16, 10)

    static func at(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        TestClock.date(month, day, hour, minute, year: year)
    }

    /// 알아들은 글자까지 견주는 줄.
    static func one(
        _ text: String, _ match: String, _ start: Date, to end: Date? = nil, now: Date = morning,
        flags: Assumptions = [], absent: Assumptions = []
    ) -> ParseCase {
        ParseCase(text: text, now: now, matches: [match], start: start, end: end, flags: flags, absent: absent)
    }

    /// 떨어진 두 곳을 알아들은 줄.
    static func split(
        _ text: String, _ matches: [String], _ start: Date, to end: Date? = nil, now: Date = morning
    ) -> ParseCase {
        ParseCase(text: text, now: now, matches: matches, start: start, end: end)
    }

    /// 시작과 끝, 짐작만 견주는 줄.
    static func row(
        _ text: String, _ start: Date, to end: Date? = nil, now: Date = morning,
        flags: Assumptions = [], absent: Assumptions = .past
    ) -> ParseCase {
        ParseCase(text: text, now: now, matches: nil, start: start, end: end, flags: flags, absent: absent)
    }

    func parse() -> DateTimeExpression? {
        DateTimeParser.firstExpression(in: text, now: now, calendar: calendar)
    }

    func check() {
        let found = parse()
        #expect(found != nil, "읽지 못했다: \(text)")
        guard let found else { return }
        if let matches {
            let source = text as NSString
            #expect(found.ranges.map { source.substring(with: $0) } == matches, "\(text)")
        }
        #expect(found.start == start, "\(text): 시작 \(describe(found.start))")
        #expect(found.end == end, "\(text): 끝 \(found.end.map(describe) ?? "없음")")
        #expect(found.assumptions.isSuperset(of: flags), "\(text): 짐작 \(found.assumptions.rawValue)")
        #expect(found.assumptions.isDisjoint(with: absent), "\(text): 짐작 \(found.assumptions.rawValue)")
    }

    private func describe(_ date: Date) -> String {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
