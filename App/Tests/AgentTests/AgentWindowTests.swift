import AppKit
import Models
import Store
import Testing
import Theme
@testable import Agent

@Suite struct AgentWindowTests {
    @Test func openingReusesOnlyItsTargetAndClosingRestoresDraft() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(location: .isolated(notesDirectory: root))
        let coordinator = AgentWindowCoordinator(store: store, theme: try Theme.bundled()) { Issue.record("\($0)") }
        coordinator.allowsKeyWindows = false
        let a = NoteID.make(), b = NoteID.make()
        func open(_ note: NoteID) throws {
            try coordinator.open(note: note, title: "같은 제목", frame: CGRect(x: 0, y: 0, width: 340, height: 220),
                                 visible: CGRect(x: 0, y: 0, width: 1000, height: 800))
        }
        try open(a)
        let first = try #require(coordinator.window(for: a))
        #expect(first.minSize.width == 260 && first.maxSize.width == 560)
        try open(a)
        #expect(first === coordinator.window(for: a))
        #expect(try store.loadConversations { Issue.record("\($0)") }.isEmpty)
        coordinator.setDraft("첫 초안", for: a)
        first.close()
        #expect(coordinator.window(for: a) == nil)
        try open(b)
        defer { coordinator.window(for: b)?.close() }
        #expect(coordinator.draft(for: b) == "")
        try open(a)
        defer { coordinator.window(for: a)?.close() }
        #expect(coordinator.draft(for: a) == "첫 초안")
        #expect(try store.loadConversations { Issue.record("\($0)") }.count == 1)
    }
}

extension AgentWindowTests {
    @Test func longReplyFollowsOnlyWhileReadingTheBottom() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = AgentWindowCoordinator(store: .init(location: .isolated(notesDirectory: root)),
                                           theme: try Theme.bundled()) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let draft = agent.newRecord()
        var request = AgentRequest(id: UUID(), text: "오늘 할 일", engine: "fixture", model: nil)
        request.answer = "짧은 답"
        draft.change { $0.requests.append(request) }
        let screen = try #require(NSScreen.main).visibleFrame
        agent.open(record: draft, title: "", frame: .init(x: screen.minX, y: screen.minY, width: 340, height: 220), visible: screen)
        let window = try #require(agent.window(id: draft.conversation.id))
        defer { window.close() }
        func settle() async throws {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
        }
        func bottom() -> Bool {
            guard let edge = draft.scrollMetrics["bottom"], let content = draft.scrollMetrics["content"] else { return false }
            return edge + 1 >= content
        }
        try await settle()
        let limit = min(420, screen.height * 0.7)
        #expect(window.frame.height < limit)
        draft.conversation.requests[0].answer = (1...32).map { "- 할 일 \($0)" }.joined(separator: "\n")
        try await settle()
        #expect(window.frame.height == limit && bottom())
        draft.verificationBottom = false
        try await settle()
        let offset = try #require(draft.scrollMetrics["offset"])
        #expect(!bottom())
        draft.conversation.requests[0].answer? += "\n- 다음 항목"
        try await settle()
        #expect(draft.scrollMetrics["offset"] == offset && !bottom())
        draft.verificationBottom = true
        try await settle()
        draft.conversation.requests[0].answer? += "\n- 마지막 항목"
        try await settle()
        #expect(bottom())
    }
}
