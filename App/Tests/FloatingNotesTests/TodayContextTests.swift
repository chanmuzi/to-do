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
