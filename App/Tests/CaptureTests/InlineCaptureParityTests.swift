import Foundation
import Testing
import DateTime
@testable import Capture

@Suite struct InlineCaptureParityTests {
    @Test(arguments: ["오늘 오후 1시 미팅", "회의 내일 오후 3시", "오후 1시 미팅", "회의 9시", "내일 오후 3시~4시"], [10, 14, 20])
    func captureAndInlineAgree(source: String, hour: Int) {
        let now = TestClock.date(11, 18, hour)
        let capture = CaptureInterpretation(raw: source, spaces: [], selectedSpace: nil,
                                           manualReminder: nil, now: now, calendar: TestClock.calendar)
        let inline = InlineDateProposal.find(in: source, caret: 0, now: now, calendar: TestClock.calendar)
        #expect(inline?.item.start == capture.schedule(now: now, calendar: TestClock.calendar)?.start)
        #expect(inline?.item.end == capture.schedule(now: now, calendar: TestClock.calendar)?.end)
        if let inline { #expect(inline.expression.ranges == capture.timeRanges) }
    }
}
