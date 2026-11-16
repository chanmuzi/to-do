import CoreGraphics
import Foundation
import Models
import Testing
@testable import Capture

/// 갈 노트 고르기, 투두로 붙이기, 리마인더 규칙, 놓이는 자리(spec 7, 20의 5·6·8번).
@Suite struct CaptureRulesTests {
    private func note(
        _ id: String, space: SpaceID?, created: Date, body: String = ""
    ) -> Note {
        Note(id: NoteID(rawValue: id), body: body, spaceID: space, created: created, modified: created)
    }

    // MARK: - 오늘 노트

    @Test func todayNoteIsTheOneCreatedTodayInThatSpace() {
        let work = CaptureFixture.work.id
        let home = CaptureFixture.home.id
        let notes = [
            note("yesterday", space: work, created: TestClock.date(11, 15, 23, 59)),
            note("home-today", space: home, created: TestClock.date(11, 16, 8, 0)),
            note("work-today", space: work, created: TestClock.date(11, 16, 9, 0)),
            note("none-today", space: nil, created: TestClock.date(11, 16, 10, 0)),
        ]
        func pick(_ space: SpaceID?) -> String? {
            CaptureDestination.todayNote(in: notes, spaceID: space, now: TestClock.now, calendar: TestClock.calendar)?
                .id.rawValue
        }
        #expect(pick(work) == "work-today")
        #expect(pick(home) == "home-today")
        #expect(pick(nil) == "none-today")
        #expect(pick(SpaceID(rawValue: "other")) == nil)
    }

    /// 오늘 만든 노트가 여럿이면 가장 먼저 만든 것이다. 목록의 차례(최근에 고친 것이 앞)와 상관없다.
    @Test func earliestNoteOfTheDayWinsRegardlessOfListOrder() {
        let work = CaptureFixture.work.id
        let notes = [
            note("later", space: work, created: TestClock.date(11, 16, 13, 0)),
            note("first", space: work, created: TestClock.date(11, 16, 0, 0)),
            note("middle", space: work, created: TestClock.date(11, 16, 9, 0)),
        ]
        let picked = CaptureDestination.todayNote(
            in: notes, spaceID: work, now: TestClock.now, calendar: TestClock.calendar
        )
        #expect(picked?.id.rawValue == "first")
        let reversed = CaptureDestination.todayNote(
            in: notes.reversed(), spaceID: work, now: TestClock.now, calendar: TestClock.calendar
        )
        #expect(reversed?.id.rawValue == "first")
    }

    @Test func dayBoundaryFollowsTheCalendar() {
        let work = CaptureFixture.work.id
        let lateNight = [note("n", space: work, created: TestClock.date(11, 16, 23, 59))]
        let afterMidnight = TestClock.date(11, 17, 0, 1)
        #expect(CaptureDestination.todayNote(
            in: lateNight, spaceID: work, now: afterMidnight, calendar: TestClock.calendar
        ) == nil)
        #expect(CaptureDestination.title(for: TestClock.now, calendar: TestClock.calendar) == "11월 16일")
    }

    // MARK: - 투두로 붙이기 (D-017: `[ ] 글자`)

    @Test(arguments: [
        ("", "[ ] 우유 사기\n"),
        ("메모", "메모\n[ ] 우유 사기\n"),
        ("메모\n", "메모\n[ ] 우유 사기\n"),
        ("[x] 끝난 일\n[ ] 남은 일\n", "[x] 끝난 일\n[ ] 남은 일\n[ ] 우유 사기\n"),
        // 맨 끝의 빈 줄은 건너뛰고 마지막 글 줄 바로 아래에 놓는다.
        ("메모\n\n\n", "메모\n[ ] 우유 사기\n"),
        ("메모\n  \n\t\n", "메모\n[ ] 우유 사기\n"),
        ("\n\n", "[ ] 우유 사기\n"),
        // 가운데의 빈 줄과 줄 끝의 공백, 들여쓰기는 그대로다.
        ("가\n\n나  \n", "가\n\n나  \n[ ] 우유 사기\n"),
        ("> 토글\n\t- 안쪽\n", "> 토글\n\t- 안쪽\n[ ] 우유 사기\n"),
        // 줄바꿈이 `\r\n`인 글은 그것을 따른다.
        ("가\r\n나\r\n", "가\r\n나\r\n[ ] 우유 사기\r\n"),
        ("가\r\n나", "가\r\n나\r\n[ ] 우유 사기\r\n"),
    ])
    func appendingATodoLine(body: String, expected: String) {
        #expect(TodoAppender.append("우유 사기", to: body) == expected)
    }

    // MARK: - 리마인더 (노트당 하나, 가장 이른 것)

    @Test func earliestReminderWins() {
        let early = TestClock.date(11, 17, 9, 0)
        let late = TestClock.date(11, 18, 9, 0)
        #expect(ReminderRule.merged(existing: nil, new: nil) == nil)
        #expect(ReminderRule.merged(existing: nil, new: late) == late)
        #expect(ReminderRule.merged(existing: early, new: nil) == early)
        #expect(ReminderRule.merged(existing: early, new: late) == early)
        #expect(ReminderRule.merged(existing: late, new: early) == early)
    }

    // MARK: - 자리 (spec 4.1: 580 x 42, 화면 가운데 아래쪽)

    @Test func barIsCenteredInTheLowerPartOfTheVisibleFrame() {
        let visible = CGRect(x: 100, y: 50, width: 1600, height: 1000)
        let frame = CapturePlacement.frame(
            size: CGSize(width: 580, height: 42), visibleFrame: visible, bottomRatio: 0.2
        )
        #expect(frame == CGRect(x: 610, y: 250, width: 580, height: 42))
        #expect(frame.midX == visible.midX)
        // Dock을 뺀 영역의 아래 끝에서 바 아래쪽까지가 영역 높이의 20%다.
        #expect(frame.minY - visible.minY == 200)
        #expect(frame.maxY < visible.midY)
    }

    @Test func barShrinksToANarrowScreenAndStaysInside() {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 30)
        let frame = CapturePlacement.frame(
            size: CGSize(width: 580, height: 42), visibleFrame: visible, bottomRatio: 0.2
        )
        #expect(frame.width == 400)
        #expect(frame.minX == 0)
        #expect(frame.minY >= visible.minY)
        let tall = CapturePlacement.frame(
            size: CGSize(width: 580, height: 42), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 100),
            bottomRatio: 0.9
        )
        #expect(tall.maxY <= 100)
    }
}
