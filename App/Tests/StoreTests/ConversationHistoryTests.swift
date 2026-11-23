import Foundation
import Models
import Store
import Testing

@MainActor @Suite struct ConversationHistoryTests {
    @Test func localMidnightSeenAndPendingSurviveReload() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(location: .isolated(notesDirectory: root))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let midnight = calendar.startOfDay(for: Date())
        var before = AgentConversation(targets: [], now: midnight.addingTimeInterval(-1))
        var question = AgentRequest(id: UUID(), text: "확인", engine: "fixture", model: nil)
        question.status = .awaitingAnswer
        before.requests = [question]
        before.seenAt = midnight
        try store.save(before)
        var after = AgentConversation(targets: [], now: midnight)
        after.requests = [question]
        try store.save(after)
        try store.save(AgentConversation(targets: []))
        let sections = ConversationDay.sections(try store.loadConversations { Issue.record("\($0)") }, calendar: calendar)
        #expect(sections.map(\.id) == [midnight, calendar.startOfDay(for: before.updatedAt)])
        #expect(sections.flatMap(\.conversations) == [after, before])
        #expect(before.needsAnswer && before.seenAt == midnight && after.seenAt == nil)
    }
}
