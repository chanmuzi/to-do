import Foundation
import Testing
import Theme
import Models

struct AbsoluteScheduleTests {
    @Test func absoluteAndRelativeRangesShareLabelsAndRespectDateBoundaries() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = c.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        let start = now.addingTimeInterval(3 * 3600)
        let item = ScheduleItem(start: start, end: start.addingTimeInterval(3600))
        let value = ReminderPresentation(item: item, now: now, options: .init(dateFormat: .absolute), calendar: c)
        #expect(value.text == "11월 18일 오후 3:00~4:00")
        #expect(value.accessibilityLabel == "일정 11월 18일 오후 3:00~4:00")
        #expect(ReminderPresentation(item: item, now: now, options: .init(), calendar: c).text == "오후 3:00~4:00")
        let tomorrow = ScheduleItem(start: c.date(byAdding: .day, value: 1, to: start)!, isDateOnly: true)
        #expect(ReminderPresentation(item: tomorrow, now: now, options: .init(), calendar: c).text == "내일")
        #expect(ReminderPresentation(item: tomorrow, now: now, options: .init(dateFormat: .absolute), calendar: c).text == "11월 19일")
        let nextYear = ScheduleItem(start: c.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 15))!)
        #expect(ReminderPresentation(item: nextYear, now: now, options: .init(dateFormat: .absolute), calendar: c).text == "2027년 1월 1일 오후 3:00")
    }
}
