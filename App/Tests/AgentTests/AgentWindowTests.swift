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
