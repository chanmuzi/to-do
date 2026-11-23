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
    @Test func upcomingSidebarUsesStartAndCalendarWeek() {
        let anchor = date(2026, 11, 18, 12)
        let owner = note("owner", day: 18)
        func label(_ start: Date, allDay: Bool = false, relativeTo now: Date? = nil) -> String {
            let item = ScheduleItem(start: start, end: start.addingTimeInterval(3600), isDateOnly: allDay)
            return UpcomingRow.note(owner, item).sidebarTime(now: now ?? anchor, calendar: calendar, clock: .koreanMeridiem)
        }
        #expect(label(date(2026, 11, 18, 17)) == "오후 5:00")
        #expect(label(date(2026, 11, 19, 10)) == "내일 10:00")
        #expect(label(date(2026, 11, 20, 9)) == "금 9:00")
        #expect(label(date(2026, 11, 20, 21)) == "금 21:00")
        #expect(label(date(2026, 11, 25, 9)) == "11월 25일")
        #expect(label(anchor, allDay: true) == "오늘")
        #expect(label(date(2026, 11, 20), allDay: true) == "금")
        #expect(label(date(2027, 1, 1), allDay: true, relativeTo: date(2026, 12, 31)) == "내일")
    }

    @Test func oldNotesStayActiveUntilManuallyArchived() {
        let value = note("note", day: 1)
        let index = LibraryIndex(notes: [value], now: now, calendar: calendar)
        #expect(index.rows(for: .all) == [value])
        #expect(index.rows(for: .archived).isEmpty)
    }
    @Test func todayExcludesArchivedReminder() {
        let today = note("today", day: 17, reminder: now)
        var old = note("old", day: 1, reminder: date(2026, 11, 17, 8))
        old.isArchived = true
        let tomorrow = note("tomorrow", day: 16, reminder: date(2026, 11, 18))
        let index = LibraryIndex(notes: [today, old, tomorrow], now: now, calendar: calendar)
        #expect(Set(index.rows(for: .today).map(\.id)) == [today.id])
        #expect(index.rows(for: .all).count == 2)
        #expect(index.upcoming.map(\.item.start) == [now, date(2026, 11, 18)])
    }
    @Test func datesAreCreationDatesAndTrashDoesNotLeakIntoViews() {
        let recent = note("recent", day: 16), trash = note("trash", day: 17)
        var old = note("old", day: 10)
        old.isArchived = true
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
        #expect(index.rows(for: .floating).map(\.id) == [b.id,c.id])
    }
    @Test func groupsPinnedThenRecentDatesWithoutDuplicates() {
        var old = note("old", day: 1)
        old.modified = date(2026, 10, 1)
        let pinned = note("pin", day: 1), today = note("today", day: 17)
        let index = LibraryIndex(notes: [old, pinned, today], windows: [pinned.id: .init(isPinned: true)],
                                 now: now, calendar: calendar)
        let groups = index.sections(for: .all)
        #expect(groups.map(\.header) == [.pinned, .today, .date("2026년 10월")])
        #expect(groups.flatMap(\.notes).map(\.id) == [pinned.id, today.id, old.id])
    }
    @Test func todayAndPinnedKeepRowOrderWithoutHeadings() throws {
        let fresh = note("오늘 작성", day: 17)
        var pinned = note("이전 작성", day: 14, reminder: now)
        pinned.modified = date(2026, 11, 15)
        let index = LibraryIndex(notes: [pinned, fresh], windows: [pinned.id: .init(isPinned: true)],
                                 now: now, calendar: calendar)
        for selection in [LibrarySelection.today, .floating] {
            let sections = index.sections(for: selection)
            #expect(sections.count == 1)
            let section = try #require(sections.first)
            #expect(section.header == nil)
            #expect(section.notes == index.rows(for: selection))
            #expect(section.notes == (selection == .today ? [fresh, pinned] : [pinned]))
        }
        #expect(LibraryIndex(notes: []).sections(for: .today).isEmpty)
    }

    @Test func archiveAndTrashGroupPinnedNotesByDate() {
        var old = note("보관된 노트", day: 16)
        old.isArchived = true
        old.modified = date(2026, 11, 16)
        let index = LibraryIndex(notes: [old], trash: [old], windows: [old.id: .init(isPinned: true)],
                                 now: now, calendar: calendar)
        for selection in [LibrarySelection.archived, .archive("2026-11"), .trash] {
            #expect(index.sections(for: selection).map(\.header) == [.date("어제")])
        }
    }

    @Test func upcomingMergesOccurrencesDeduplicatesLinksWithoutTruncating() {
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
        #expect(rows.map(\.item.id) == ["진행", "노트 알림", "다음 회차", "외부1", "외부2", "외부3", "외부4"])
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

    @Test func newNoteProposalUsesNoteListSubtitle() {
        let markdown = "[ ] **소개 글** 고치기\r\n\t- [x] 캡처 준비"
        let preview = LibraryPreview(title: "이번 주 할 일", markdown: markdown)
        let note = Note(id: .make(), title: preview.title, body: markdown, created: now, modified: now)
        #expect(preview.subtitle == "소개 글 고치기, 캡처 준비")
        #expect(preview.subtitle == LibraryPreview(note).subtitle)
        #expect(LibraryPreview(title: "빈 노트", markdown: "").subtitle.isEmpty)
    }

    @Test func taskProgressExcludesCode() {
        let summary = LibraryPreview(Note(id: .make(), body: "[ ] a\n- [x] b\n```\n[x] code\n```\n\t[X] c", created: Date(), modified: Date()))
        #expect(summary.completed == 2 && summary.total == 3)
    }
}

extension LibraryIndexTests {
    @Test func reusedLocalIdentifierKeepsBothDestinations() {
        var owner = note("연결 노트", day: 17)
        var item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "회의")
        item.link = .init(localID: "local", externalID: "original", kind: .event)
        owner.schedules = [item]
        var other = item
        other.link = .init(localID: "local", externalID: "copy", kind: .event)
        let external = CalendarEvent(item: other, destination: nil)
        let rows = LibraryIndex(notes: [owner], events: [external], now: now, calendar: calendar).upcoming
        #expect(rows.contains { if case .note(let note, _) = $0 { note.id == owner.id } else { false } })
        #expect(rows.contains { if case .calendar(let event) = $0 { event == external } else { false } })
    }
}
