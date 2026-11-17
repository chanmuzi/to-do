import Foundation
import Testing
import Models
import Theme

@Suite struct SchedulePresentationTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 14))! }
    @Test func nextUpcomingWinsOverOverdueAndCompletedItems() {
        let past = ScheduleItem(start: now.addingTimeInterval(-3600))
        let early = ScheduleItem(start: now.addingTimeInterval(600))
        let late = ScheduleItem(start: now.addingTimeInterval(3600))
        let complete = ScheduleItem(start: now, isCompleted: true)
        let note = Note(id: .make(), schedules: [late, past, complete, early], created: now, modified: now)
        #expect(note.displayedSchedule(at: now)?.id == early.id)
    }
    @Test func rangeUsesCommonFormatterAndCalendarIconEvenWhenImminent() {
        let item = ScheduleItem(start: now.addingTimeInterval(600), end: now.addingTimeInterval(3600))
        let value = ReminderPresentation(item: item, now: now, options: .init(), calendar: calendar)
        #expect(value.text == "오후 2:10~3:00")
        #expect(value.symbolName == "calendar" && value.status == .imminent)
        #expect(value.color == .warn && !value.isRinging)
        #expect(value.accessibilityLabel.contains("임박"))
        #expect(ReminderPresentation(item: item, now: now, options: .init(reminder: .iconOnly), calendar: calendar).text == nil)
    }
    @Test func dateOnlyDoesNotBecomeOverdueAtMidnightOrShowFakeClock() {
        let item = ScheduleItem(start: calendar.startOfDay(for: now), isDateOnly: true)
        let value = ReminderPresentation(item: item, now: now, options: .init(), calendar: calendar)
        #expect(value.text == "오늘" && value.status == .scheduled)
    }
}
