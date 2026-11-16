import Foundation
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct ReminderPresentationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    /// 2026-11-16은 월요일이다.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func presentation(
        _ reminder: Date, now: Date, _ options: NotePanelDisplayOptions = NotePanelDisplayOptions()
    ) -> ReminderPresentation {
        ReminderPresentation(reminder: reminder, now: now, options: options, calendar: calendar)
    }

    @Test func scheduledShowsTheClockInTheChromeColor() {
        let shown = presentation(date(16, 15), now: date(16, 9))
        #expect(shown.status == .scheduled)
        #expect(shown.text == "3:00 PM")
        #expect(shown.symbolName == "clock")
        #expect(shown.color == .text2)
        #expect(shown.textStyle == .ui)
        #expect(!shown.isRinging)
    }

    @Test func imminentStartsFifteenMinutesBeforeAndRingsInWarn() {
        #expect(presentation(date(16, 15), now: date(16, 14, 44)).status == .scheduled)
        let shown = presentation(date(16, 15), now: date(16, 14, 45))
        #expect(shown.status == .imminent)
        #expect(shown.symbolName == "bell")
        #expect(shown.color == .warn)
        #expect(shown.textStyle == .uiStrong)
        #expect(shown.isRinging)
    }

    @Test func overdueStaysInWarnWithTheClockAndRegularWeight() {
        let shown = presentation(date(16, 9, 30), now: date(16, 15))
        #expect(shown.status == .overdue)
        #expect(shown.text == "9:30 AM")
        #expect(shown.symbolName == "clock")
        #expect(shown.color == .warn)
        #expect(shown.textStyle == .ui)
    }

    @Test func otherDaysGetADayPrefix() {
        let now = date(16, 9)
        #expect(presentation(date(17, 10), now: now).text == "내일 10:00 AM")
        #expect(presentation(date(18, 14), now: now).text == "수 2:00 PM")
        #expect(presentation(date(15, 14), now: now).text == "어제 2:00 PM")
        #expect(presentation(date(30, 8, 5), now: now).text == "11/30 8:05 AM")
    }

    @Test func clockFormats() {
        let now = date(16, 9)
        #expect(presentation(date(16, 15), now: now, .init(clock: .koreanMeridiem)).text == "오후 3:00")
        #expect(presentation(date(16, 15), now: now, .init(clock: .twentyFourHour)).text == "15:00")
        #expect(presentation(date(16, 0, 5), now: date(15, 23), .init(clock: .twelveHour)).text == "내일 12:05 AM")
        #expect(presentation(date(16, 12), now: now, .init(clock: .koreanMeridiem)).text == "오후 12:00")
    }

    @Test func relativeModeShowsOnlyTheRemainingTime() {
        let relative = NotePanelDisplayOptions(reminder: .relative)
        #expect(presentation(date(16, 15), now: date(16, 14, 48), relative).text == "12분 후")
        #expect(presentation(date(16, 15), now: date(16, 12), relative).text == "3시간 후")
        #expect(presentation(date(17, 10), now: date(16, 12), relative).text == "내일")
        #expect(presentation(date(19, 10), now: date(16, 12), relative).text == "3일 후")
        #expect(presentation(date(16, 9), now: date(16, 12), relative).text == "지남")
    }

    @Test func iconOnlyModeHasNoText() {
        let shown = presentation(date(16, 15), now: date(16, 14, 50), .init(reminder: .iconOnly))
        #expect(shown.text == nil)
        #expect(shown.symbolName == "bell")
    }

    @Test func nextRefreshIsTheNextMomentTheDisplayChanges() {
        let options = NotePanelDisplayOptions()
        let reminder = date(16, 15)
        func next(_ now: Date, _ options: NotePanelDisplayOptions) -> Date? {
            ReminderPresentation.nextRefresh(reminder: reminder, now: now, options: options, calendar: calendar)
        }
        #expect(next(date(16, 9), options) == date(16, 14, 45))
        #expect(next(date(16, 14, 50), options) == reminder)
        #expect(next(date(16, 16), options) == date(17, 0))
        #expect(next(date(15, 9), options) == date(16, 0))
        let relative = NotePanelDisplayOptions(reminder: .relative)
        #expect(next(date(16, 14, 50).addingTimeInterval(20), relative) == date(16, 14, 51))
    }
}
