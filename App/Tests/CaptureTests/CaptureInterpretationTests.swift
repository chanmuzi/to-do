import Foundation
import Models
import Testing
@testable import Capture

/// 적은 글 한 줄에서 스페이스와 리마인더를 읽는다(spec 7).
@Suite struct CaptureInterpretationTests {
    private let spaces = [CaptureFixture.work, CaptureFixture.home]

    private func interpret(
        _ raw: String, selected: SpaceID? = nil, manual: Date? = nil
    ) -> CaptureInterpretation {
        CaptureInterpretation(
            raw: raw, spaces: spaces, selectedSpace: selected, manualReminder: manual,
            now: TestClock.now, calendar: TestClock.calendar
        )
    }

    @Test func plainTextKeepsTheSelectedSpaceAndHasNoReminder() {
        let entry = interpret("우유 사기", selected: CaptureFixture.home.id)
        #expect(entry.text == "우유 사기")
        #expect(entry.spaceID == CaptureFixture.home.id)
        #expect(entry.reminder == nil)
        #expect(entry.timeRange == nil)
    }

    /// 시간 표현은 리마인더가 되고, 넣는 글에는 적은 그대로 남는다.
    @Test func timeExpressionBecomesTheReminderAndStaysInTheText() {
        let entry = interpret("릴리즈 노트 초안 쓰기 내일 오전 10시", selected: CaptureFixture.work.id)
        #expect(entry.text == "릴리즈 노트 초안 쓰기 내일 오전 10시")
        #expect(entry.reminder == TestClock.date(11, 17, 10, 0))
        #expect(entry.timeRange == NSRange(location: 13, length: 9))
    }

    @Test(arguments: [
        ("#개인 우유 사기", "우유 사기"),
        ("우유 사기 #개인", "우유 사기"),
        ("우유 #개인 사기", "우유 사기"),
        ("#개인", ""),
    ])
    func spaceTokenChoosesTheSpaceAndLeavesTheText(raw: String, expectedText: String) {
        let entry = interpret(raw, selected: CaptureFixture.work.id)
        #expect(entry.spaceID == CaptureFixture.home.id)
        #expect(entry.text == expectedText)
    }

    @Test func spaceTokenIgnoresCase() {
        let named = [Space(id: SpaceID(rawValue: "w"), name: "Work", icon: .emoji("💼"))]
        let entry = CaptureInterpretation(
            raw: "#work ship it", spaces: named, selectedSpace: nil, manualReminder: nil,
            now: TestClock.now, calendar: TestClock.calendar
        )
        #expect(entry.spaceID == SpaceID(rawValue: "w"))
        #expect(entry.text == "ship it")
    }

    /// 이름과 똑같지 않거나 낱말 가운데에 있으면 스페이스 표시가 아니다.
    @Test(arguments: ["#개인적인 일", "C#개인 공부", "#없는곳 메모", "# 개인 메모"])
    func textThatOnlyLooksLikeATokenIsKept(raw: String) {
        let entry = interpret(raw, selected: CaptureFixture.work.id)
        #expect(entry.spaceID == CaptureFixture.work.id)
        #expect(entry.text == raw)
    }

    @Test func theFirstSpaceTokenWinsAndLongerNamesMatchFirst() {
        #expect(interpret("#회사 #개인 메모").spaceID == CaptureFixture.work.id)
        let overlapping = [
            Space(id: SpaceID(rawValue: "a"), name: "회사", icon: .emoji("a")),
            Space(id: SpaceID(rawValue: "b"), name: "회사 밖", icon: .emoji("b")),
        ]
        let entry = CaptureInterpretation(
            raw: "#회사 밖 산책", spaces: overlapping, selectedSpace: nil, manualReminder: nil,
            now: TestClock.now, calendar: TestClock.calendar
        )
        #expect(entry.spaceID == SpaceID(rawValue: "b"))
        #expect(entry.text == "산책")
    }

    /// ⌘R로 고른 리마인더가 글에서 읽은 시간보다 우선하고, 그때는 밑줄을 긋지 않는다.
    @Test func manualReminderWinsOverTheParsedTime() {
        let manual = TestClock.date(11, 18, 9, 0)
        let entry = interpret("내일 10시 회의", manual: manual)
        #expect(entry.reminder == manual)
        #expect(entry.timeRange == nil)
        #expect(entry.text == "내일 10시 회의")
    }

    @Test func spaceTokenAndTimeTogether() {
        let entry = interpret("#개인 치과 금요일 3시", selected: CaptureFixture.work.id)
        #expect(entry.spaceID == CaptureFixture.home.id)
        #expect(entry.text == "치과 금요일 3시")
        #expect(entry.reminder == TestClock.date(11, 20, 15, 0))
        // 밑줄 자리는 입력 칸의 글(표시를 빼기 전) 기준이다.
        #expect(entry.timeRange == NSRange(location: 7, length: 6))
    }

    @Test func whitespaceIsFlattenedAndBlankTextIsEmpty() {
        #expect(interpret("  우유\n사기\t 두 개  ").text == "우유 사기 두 개")
        #expect(interpret("   ").isEmpty)
        #expect(interpret("").isEmpty)
    }

    // MARK: - ⇥, ⌘R

    @Test func tabCyclesThroughSpacesThenNoSpace() {
        let work = CaptureFixture.work.id
        let home = CaptureFixture.home.id
        #expect(CaptureSpaceCycle.next(after: work, in: spaces) == home)
        #expect(CaptureSpaceCycle.next(after: home, in: spaces) == nil)
        #expect(CaptureSpaceCycle.next(after: nil, in: spaces) == work)
        #expect(CaptureSpaceCycle.next(after: work, in: spaces, backward: true) == nil)
        #expect(CaptureSpaceCycle.next(after: nil, in: spaces, backward: true) == home)
        #expect(CaptureSpaceCycle.next(after: nil, in: []) == nil)
        // 없어진 스페이스에서 시작하면 첫 스페이스로 간다.
        #expect(CaptureSpaceCycle.next(after: SpaceID(rawValue: "gone"), in: spaces) == work)
    }

    @Test func initialSpaceIsTheRememberedOneOrTheFirst() {
        #expect(CaptureSpaceCycle.initial(remembered: nil, in: spaces) == CaptureFixture.work.id)
        #expect(CaptureSpaceCycle.initial(remembered: .some(CaptureFixture.home.id), in: spaces) == CaptureFixture.home.id)
        #expect(CaptureSpaceCycle.initial(remembered: .some(nil), in: spaces) == nil)
        #expect(CaptureSpaceCycle.initial(remembered: .some(SpaceID(rawValue: "gone")), in: spaces) == CaptureFixture.work.id)
        #expect(CaptureSpaceCycle.initial(remembered: nil, in: []) == nil)
    }

    @Test func reminderPresetsCycleAndReturnToNone() {
        let now = TestClock.now
        let calendar = TestClock.calendar
        let expected = [
            TestClock.date(11, 16, 15, 0), TestClock.date(11, 16, 18, 0),
            TestClock.date(11, 17, 9, 0), TestClock.date(11, 23, 9, 0),
        ]
        #expect(CaptureReminderPresets.dates(now: now, calendar: calendar) == expected)
        var current: Date?
        var visited: [Date?] = []
        for _ in 0..<5 {
            current = CaptureReminderPresets.next(after: current, now: now, calendar: calendar)
            visited.append(current)
        }
        #expect(visited == expected.map(Optional.some) + [nil])
        // 저녁 6시가 지났으면 그 값은 빠진다.
        let evening = TestClock.date(11, 16, 19, 30)
        #expect(CaptureReminderPresets.dates(now: evening, calendar: calendar).count == 3)
    }

    @Test func reminderTextFollowsTheDesign() {
        func text(_ date: Date) -> String {
            CaptureReminderText.text(for: date, now: TestClock.now, calendar: TestClock.calendar)
        }
        #expect(text(TestClock.date(11, 17, 10, 0)) == "내일 10:00 AM")
        #expect(text(TestClock.date(11, 16, 15, 0)) == "3:00 PM")
        #expect(text(TestClock.date(11, 17, 0, 0)) == "내일 12:00 AM")
        #expect(text(TestClock.date(11, 20, 15, 30)) == "금 3:30 PM")
        #expect(text(TestClock.date(12, 25, 9, 0)) == "12/25 9:00 AM")
    }
}
