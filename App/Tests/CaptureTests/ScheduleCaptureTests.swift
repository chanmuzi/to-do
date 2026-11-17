import Foundation
import Testing
import Models
@testable import Capture

@Suite struct ScheduleCaptureTests {
    private func entry(_ raw: String) -> CaptureInterpretation {
        CaptureInterpretation(raw: raw, spaces: [], selectedSpace: nil, manualReminder: nil,
                              now: TestClock.now, calendar: TestClock.calendar)
    }
    @Test func rangeBecomesEventAndOnlyRecognizedRangesAreRemoved() throws {
        let value = entry("내일 오후 3~4시 회의")
        #expect(value.text == "회의")
        let item = try #require(value.schedule(now: TestClock.now, line: 0, calendar: TestClock.calendar))
        #expect(item.kind == .event)
        #expect(item.start == TestClock.date(11, 17, 15, 0))
        #expect(item.end == TestClock.date(11, 17, 16, 0))
        #expect(item.todo?.completed(in: "[ ] 회의\n") == false)
    }
    @Test func dateOnlyAndDayPartAreDifferent() throws {
        let dateOnly = try #require(entry("내일 우유").schedule(now: TestClock.now, calendar: TestClock.calendar))
        #expect(dateOnly.isDateOnly)
        #expect(dateOnly.start == TestClock.date(11, 17, 0, 0))
        let evening = try #require(entry("내일 저녁 우유").schedule(now: TestClock.now, calendar: TestClock.calendar))
        #expect(!evening.isDateOnly)
        #expect(evening.start == TestClock.date(11, 17, 19, 0))
    }
    @Test func allDayRangeIncludesItsLastDayAndExistingTodoMarkerStillMatches() throws {
        let value = entry("[ ] 11/20~11/22 출장")
        let item = try #require(value.schedule(now: TestClock.now, line: 0, calendar: TestClock.calendar))
        #expect(item.isDateOnly && item.kind == .event)
        #expect(item.start == TestClock.date(11, 20, 0, 0))
        #expect(item.end == TestClock.date(11, 23, 0, 0))
        #expect(item.todo?.completed(in: "[ ] 출장\n") == false)
    }
}
