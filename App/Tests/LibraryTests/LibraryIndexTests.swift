import Foundation
import Models
import Testing
@testable import Library

@Suite struct LibraryIndexTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    var now: Date { date(2026, 11, 17, 12) }
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func note(_ id: String, day: Int, reminder: Date? = nil, space: String? = "work") -> Note {
        Note(id: .init(rawValue: id), title: id, spaceID: space.map(SpaceID.init(rawValue:)), reminder: reminder,
             created: date(2026, 11, day), modified: now)
    }
    @Test(arguments: [9, 10, 11, 16, 17]) func archiveUsesCreatedDayAndSevenCalendarDays(day: Int) {
        let value = note("note", day: day)
        let index = LibraryIndex(notes: [value], now: now, calendar: calendar)
        #expect(index.isArchived(value) == (day <= 10))
        #expect(index.rows(for: .space(.init(rawValue: "work"))).count == (day <= 10 ? 0 : 1))
    }
    @Test func todayIsUnionWithoutDuplicatesAndIncludesArchivedReminder() {
        let today = note("today", day: 17, reminder: now)
        let old = note("old", day: 1, reminder: date(2026, 11, 17, 8))
        let tomorrow = note("tomorrow", day: 16, reminder: date(2026, 11, 18))
        let index = LibraryIndex(notes: [today, old, tomorrow], now: now, calendar: calendar)
        #expect(Set(index.rows(for: .today).map(\.id)) == [today.id, old.id])
        #expect(index.rows(for: .all).count == 3)
        #expect(index.upcoming.map(\.item.start) == [now, date(2026, 11, 18)])
    }
    @Test func datesAreCreationDatesAndTrashDoesNotLeakIntoViews() {
        let recent = note("recent", day: 16), old = note("old", day: 10), trash = note("trash", day: 17)
        let index = LibraryIndex(notes: [recent, old], trash: [trash], now: now, calendar: calendar)
        #expect(index.days(in: .init(rawValue: "work")) == [date(2026, 11, 16)])
        #expect(index.rows(for: .today).isEmpty)
        #expect(index.rows(for: .trash).map(\.id) == [trash.id])
        #expect(index.archiveMonths == ["2026-11"])
        #expect(index.rows(for: .archive("2026-11")).map(\.id) == [old.id])
    }
    @Test func floatingUsesEditDateEvenWhenAnOlderWindowIsInFront() {
        let a = note("a", day: 17), c = note("c", day: 17)
        var b = note("b", day: 17)
        b.modified = now.addingTimeInterval(5)
        let index = LibraryIndex(notes: [a,b,c], windows: [
            a.id: NoteWindowState(isPinned: false, isOpen: true, stackOrder: 5),
            b.id: NoteWindowState(isOpen: true, stackOrder: 2), c.id: NoteWindowState(isOpen: false)
        ], now: now, calendar: calendar)
        #expect(index.rows(for: .floating).map(\.id) == [b.id,a.id])
    }
    @Test func localMidnightAndMonthRollover() {
        let old = Note(id: .make(), created: date(2026, 10, 31, 23), modified: now)
        let index = LibraryIndex(notes: [old], now: date(2026, 11, 7), calendar: calendar)
        #expect(index.isArchived(old))
        #expect(index.archiveMonths == ["2026-10"])
    }
    @Test func daylightSavingUsesCalendarDays() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let created = cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let boundary = cal.date(from: DateComponents(year: 2026, month: 3, day: 14))!
        let value = Note(id: .make(), created: created, modified: created)
        #expect(LibraryIndex(notes: [value], now: boundary, calendar: cal).isArchived(value))
        #expect(!LibraryIndex(notes: [value], now: boundary.addingTimeInterval(-1), calendar: cal).isArchived(value))
    }
    @Test func searchAndCountsUseSameRows() {
        var a = note("계획", day: 17, space: nil); a.body = "Swift 배포"
        let index = LibraryIndex(notes: [a, note("b", day: 17)], now: now, calendar: calendar)
        #expect(index.rows(for: .all, query: "swift").map(\.id) == [a.id])
        #expect(index.rows(for: .space(nil)).count == 1)
        #expect(index.rows(for: .all, query: "없음").isEmpty)
    }
    @Test func upcomingMergesOccurrencesDeduplicatesLinksAndCapsAfterSorting() {
        let interval = LibraryIndex.upcomingInterval(now: now, calendar: calendar)
        let link = ScheduleItem.Link(localID: "회의", externalID: "회사-회의", kind: .event)
        let ongoing = ScheduleItem(id: "진행", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600), link: link)
        let later = ScheduleItem(id: "다음 회차", start: now.addingTimeInterval(60), end: now.addingTimeInterval(180), link: link)
        let done = ScheduleItem(id: "완료", start: now, isCompleted: true)
        let ended = ScheduleItem(id: "끝", start: now.addingTimeInterval(-120), end: now)
        var owner = note("노트", day: 17)
        owner.schedules = [ongoing, done, ended, ScheduleItem(id: "경계", start: interval.end),
                           ScheduleItem(id: "노트 알림", start: now.addingTimeInterval(30))]
        let extra = (1...4).map { n in
            CalendarEvent(item: ScheduleItem(id: "외부\(n)", start: now.addingTimeInterval(Double(n * 120)),
                                             end: now.addingTimeInterval(3600)), destination: nil)
        }
        let events = extra + [CalendarEvent(item: ongoing, destination: nil, recurring: true),
                              CalendarEvent(item: later, destination: nil, recurring: true)]
        let rows = LibraryIndex(notes: [owner], events: events, now: now, calendar: calendar).upcoming
        #expect(rows.map(\.item.id) == ["진행", "노트 알림", "다음 회차", "외부1", "외부2"])
        guard case .note(let first, _) = rows.first else { Issue.record("노트 연결을 우선해야 합니다"); return }
        #expect(first.id == owner.id)
        #expect(LibraryIndex(notes: [], now: now).upcoming.isEmpty)
    }

    @Test func externalIDFallbackKeepsIndependentCalendarCopies() {
        func event(_ id: String) -> ScheduleItem {
            ScheduleItem(id: id, start: now, end: now.addingTimeInterval(60),
                         link: .init(localID: id, externalID: "공유 UID", kind: .event))
        }
        var owner = note("연결 노트", day: 17)
        owner.schedules = [event("원본")]
        let current = CalendarEvent(item: event("원본"), destination: nil)
        let copy = CalendarEvent(item: event("사본"), destination: nil)
        let both = LibraryIndex(notes: [owner], events: [current, copy], now: now).upcoming
        #expect(both.count == 2)
        let changedLocalID = LibraryIndex(notes: [owner], events: [copy], now: now).upcoming
        #expect(changedLocalID.count == 1)
        guard case .note = changedLocalID.first else { Issue.record("노트 연결을 유지해야 합니다"); return }
    }

    @Test func taskProgressExcludesCode() {
        let summary = LibraryPreview(Note(id: .make(), body: "[ ] a\n- [x] b\n```\n[x] code\n```\n\t[X] c", created: Date(), modified: Date()))
        #expect(summary.completed == 2 && summary.total == 3)
    }
}
