import Agent
import Store
import Library
import Foundation
import Models
import Scheduling
import Testing
@testable import FloatingNotes

@MainActor
@Suite struct TodayContextTests {
    private typealias Object = [String: Any]
    private let now = Date(timeIntervalSince1970: 1_795_507_200)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func prompt(_ fixture: AppFixture, _ bridge: FakeCalendarBridge, instructions: String = "",
                        selectedID: ((ScheduleItem.Kind) -> String?)? = nil) async throws -> (String, Object) {
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { bridge })
        if let selectedID { service.preferredID = selectedID }
        var execution = AgentExecution(location: fixture.location, directory: nil)
        execution.scheduleContext = service.todayContext
        let request = AgentRequest(id: UUID(), text: "오늘 할 일", engine: "fixture", model: nil)
        let raw = try await execution.prompt(.init(targets: []), request, instructions: instructions, now: now, calendar: calendar)
        let object = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? Object)
        #expect(bridge.authorizationRequests.isEmpty && bridge.authorizationPromptAttempts.isEmpty && bridge.saves == 0)
        return (raw, try #require(object["today"] as? Object))
    }

    @Test func selectedCalendarsLocalDayAndNoteLinks() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let fake = FakeCalendarBridge()
        let day = try #require(calendar.dateInterval(of: .day, for: now))
        let link = ScheduleItem.Link(localID: "linked", externalID: nil, kind: .event)
        let meeting = ScheduleItem(start: day.start, end: day.end, isDateOnly: true, title: "휴가", link: link)
        let note = try fixture.notes.create(.init(title: "팀", schedules: [meeting, .init(start: now, title: "로컬")]))
        fake.items["linked"] = meeting
        fake.items["overdue"] = .init(start: day.start.addingTimeInterval(-600), title: "반납")
        fake.items["tomorrow"] = .init(start: day.end, title: "내일")
        fake.items["completed"] = .init(start: day.start, isCompleted: true, title: "완료")
        fake.items["other"] = .init(start: now, title: "다른 목록", link: .init(localID: "other", externalID: nil))
        fake.linkedDestinations["other"] = fake.additionalChoices[.reminder]?.first?.destination
        var remote = meeting
        remote.link = .init(localID: "옮겨진 ID", externalID: "휴가 ID", kind: .event)
        fake.items["linked"] = remote
        try fixture.notes.update(note.id) { $0.schedules[0].link?.externalID = "휴가 ID" }
        let (_, today) = try await prompt(fixture, fake)
        let events = try #require((today["events"] as? Object)?["items"] as? [Object])
        #expect(events.count == 1)
        let row = try #require(events.first)
        #expect(row["title"] as? String == "휴가" && row["allDay"] as? Bool == true && row["end"] is String)
        #expect(row["source"] as? String == "Float 노트" && row["noteFile"] as? String == note.id.rawValue + ".md")
        let reminders = try #require((today["reminders"] as? Object)?["items"] as? [Object])
        #expect(reminders.compactMap { $0["title"] as? String } == ["로컬", "반납"])
        #expect(reminders.last?["source"] as? String == "외부 캘린더")
        let (_, selected) = try await prompt(fixture, fake, selectedID: { $0 == .reminder ? "shopping" : "missing" })
        let selectedItems = try #require((selected["reminders"] as? Object)?["items"] as? [Object])
        #expect(selectedItems.compactMap { $0["title"] as? String } == ["다른 목록", "로컬"])
        #expect((selected["events"] as? Object)?["status"] as? String == "알 수 없음")
    }

    @Test func unknownAndEmptyAreIndependent() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let fake = FakeCalendarBridge()
        for denied in [CalendarAccess.needsRequest, .blocked] {
            fake.accessByKind[.reminder] = denied
            let (_, today) = try await prompt(fixture, fake)
            #expect((today["events"] as? Object)?["status"] as? String == "없음")
            #expect((today["reminders"] as? Object)?["status"] as? String == "알 수 없음")
        }
    }

    @Test func nearestItemsSurviveCountAndByteLimits() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let fake = FakeCalendarBridge()
        for i in 0..<25 {
            let date = now.addingTimeInterval(Double(i))
            fake.items["r" + String(i)] = .init(start: date, title: "할 일 " + String(i))
            fake.items["e" + String(i)] = .init(start: date, end: date.addingTimeInterval(1), title: "일정 " + String(i))
        }
        let (_, today) = try await prompt(fixture, fake)
        for kind in ["events", "reminders"] {
            let section = try #require(today[kind] as? Object)
            #expect((section["items"] as? [Object])?.count == 20 && section["omitted"] as? Int == 5)
        }
        let (raw, limited) = try await prompt(fixture, fake, instructions: String(repeating: "a", count: 94 * 1024))
        #expect(raw.utf8.count <= 96 * 1024)
        for kind in ["events", "reminders"] {
            let section = try #require(limited[kind] as? Object)
            let items = try #require(section["items"] as? [Object])
            #expect(!items.isEmpty && items.count < 20)
            #expect(section["omitted"] as? Int == 25 - items.count)
            #expect((items.first?["title"] as? String)?.hasSuffix(" 0") == true)
        }
    }
}

extension TodayContextTests {
    @Test func requestSnapshotResolvesViewsPeriodsAndReportsTruncation() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let space = Space(id: .make(), name: "업무", icon: .none)
        let start = calendar.startOfDay(for: now)
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let old = start.addingTimeInterval(-86400)
        var notes = (0..<56).map { i in
            Note(id: .init(rawValue: "업무-\(i)"), title: "계획", spaceID: space.id,
                 created: old, modified: start.addingTimeInterval(Double(i)))
        }
        notes[0].isArchived = true
        notes[1].schedules = [.init(start: now)]
        notes.append(.init(id: .make(), title: "다음 날", created: end, modified: end))
        let windows = [notes[2].id: NoteWindowState(isPinned: true)]
        let index = LibraryIndex(notes: notes, windows: windows, now: now, calendar: calendar)
        var execution = AgentExecution(location: fixture.location, directory: nil)
        execution.resolveContext = { items, _, _ in AgentPromptContext.resolve(items, index: index, spaces: [space]) }
        var request = AgentRequest(id: UUID(), text: "정리", engine: "fixture", model: nil)
        request.context = [.space(space.id), .view(.today), .view(.pinned), .period(.today), .note(notes[0].id)]
        let draft = AgentConversation(origin: nil, context: [])
        func rows(_ instructions: String = "") async throws -> [Object] {
            let raw = try await execution.prompt(draft, request, instructions: instructions, now: now, calendar: calendar)
            #expect(raw.utf8.count <= 96 * 1024)
            let json = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? Object)
            return try #require(json["context"] as? [Object])
        }
        let resolved = try await rows()
        #expect(resolved.compactMap { $0["kind"] as? String } == ["space", "view", "view", "period", "note"])
        #expect(resolved[0]["name"] as? String == "업무" && resolved[0]["omitted"] as? Int == 5)
        #expect((resolved[0]["notes"] as? [String])?.first == "업무-55.md")
        #expect(resolved[1]["notes"] as? [String] == ["업무-1.md"])
        #expect(resolved[2]["notes"] as? [String] == ["업무-2.md"])
        #expect(resolved[3]["omitted"] as? Int == 6 && resolved[4]["notes"] as? [String] == ["업무-0.md"])
        let limited = try await rows(String(repeating: "x", count: 96 * 1024 - 2100))
        let names = try #require(limited.first?["notes"] as? [String])
        #expect(names.count < 50 && limited.first?["omitted"] as? Int == 55 - names.count)
    }
}

extension TodayContextTests {
    @Test func queuedPromptUsesTheSelectionAtSubmission() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(location: .isolated(notesDirectory: root))
        let draft = AgentDraft(.init(origin: nil, context: [.view(.pinned)]), store: store)
        var seen: [[AgentContextItem]?] = []
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, request, _ in
            seen.append(request.context)
            return "테스트 답"
        }
        #expect(queue.submit(draft, text: "하나"))
        draft.change { $0.context = [.period(.thisWeek)] }
        #expect(queue.submit(draft, text: "둘"))
        draft.change { $0.context = [] }
        while let task = queue.task { await task.value }
        let saved = try #require(store.loadConversations { Issue.record("\($0)") }.first)
        #expect(seen == [[.view(.pinned)], [.period(.thisWeek)]])
        #expect(saved.context.isEmpty && saved.requests.map(\.context) == seen)
    }
}
