import Foundation
import Models
import Store
import Testing
@testable import Agent

@Suite struct AgentContextPickerTests {
    @Test func recentSearchNavigationAndMultipleSelection() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let space = Space(id: .make(), name: "업무", icon: .none)
        let now = Date()
        let notes = (0..<12).map { i in
            var note = Note(id: .make(), title: "업무 \(i)", spaceID: space.id, created: now, modified: now)
            note.isArchived = i == 0
            return note
        }
        let windows = Dictionary(uniqueKeysWithValues: notes.dropLast().enumerated().map {
            ($0.element.id, NoteWindowState(lastOpened: now.addingTimeInterval(Double($0.offset))))
        })
        let catalog = AgentContextCatalog(notes: notes, spaces: [space], windows: windows)
        let draft = AgentDraft(.init(origin: notes[0].id, context: []), store: .init(location: .isolated(notesDirectory: root)))
        let picker = AgentContextPickerModel(draft: draft, catalog: catalog)
        #expect(picker.rows.prefix(7) == [.header("보기와 날짜"), .item(.view(.pinned)), .item(.view(.today)),
                                         .item(.period(.thisWeek)), .item(.period(.lastSevenDays)), .chooseDay, .header("스페이스")])
        #expect(Array(picker.rows.suffix(8)) == (3...10).reversed().map { .item(.note(notes[$0].id)) })
        picker.query = "업무"
        #expect(picker.rows.first == .item(.space(space.id)) && picker.rows.last == .item(.note(notes[0].id)))
        picker.toggle(picker.selection)
        picker.enter(space.id)
        #expect(picker.choices.count == 11 && picker.query.isEmpty)
        picker.move(1)
        picker.toggle(picker.selection)
        #expect(draft.conversation.context.count == 2)
        picker.toggle(picker.selection)
        picker.back()
        #expect(picker.query == "업무" && picker.selection == .item(.space(space.id)))
        picker.toggle(picker.selection)
        picker.choose(now)
        #expect(draft.conversation.context == [.period(.day(.init(now)))] && draft.conversation.origin == notes[0].id)
    }

    @Test func localWeekSevenDaysAndChosenDaySpanDaylightSaving() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        cal.firstWeekday = 2
        let now = try #require(cal.date(from: .init(year: 2026, month: 3, day: 9, hour: 12)))
        let week = try #require(AgentContextItem.Period.thisWeek.interval(at: now, calendar: cal))
        #expect(week.start == cal.startOfDay(for: now))
        let seven = try #require(AgentContextItem.Period.lastSevenDays.interval(at: now, calendar: cal))
        #expect(seven.duration == (7 * 24 - 1) * 3600)
        let sunday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let day = AgentContextItem.Period.day(.init(sunday, timeZone: cal.timeZone))
        let interval = try #require(day.interval(at: now, calendar: cal))
        #expect(interval.duration == 23.0 * 3600)
    }
}
