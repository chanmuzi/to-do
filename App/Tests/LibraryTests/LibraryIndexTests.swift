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
        #expect(index.upcoming.map(\.id) == [today.id, tomorrow.id])
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
    @Test func floatingUsesOpenStateAndStackOrderEvenWhenUnpinned() {
        let a = note("a", day: 17), b = note("b", day: 17), c = note("c", day: 17)
        let index = LibraryIndex(notes: [a,b,c], windows: [
            a.id: NoteWindowState(isPinned: false, isOpen: true, stackOrder: 5),
            b.id: NoteWindowState(isOpen: true, stackOrder: 2), c.id: NoteWindowState(isOpen: false)
        ], now: now, calendar: calendar)
        #expect(index.rows(for: .floating).map(\.id) == [a.id,b.id])
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
    @Test func taskProgressExcludesCode() {
        #expect(LibraryPreview.progress("[ ] a\n- [x] b\n```\n[x] code\n```\n\t[X] c") == "2/3")
    }
}
