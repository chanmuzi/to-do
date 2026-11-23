@testable import Agent
import AppKit
@_spi(Verification) import Capture
import FloatSettings
import Library
import Models
import Scheduling
import Store
import Testing
import Theme
@testable import FloatingNotes

@Suite(.serialized) @MainActor struct AgentButtonClickTests {
    private func buttons(in window: NSWindow) -> [String: AnyObject] {
        var result: [String: AnyObject] = [:]
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: AnyObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let element = object as? NSObject, element.responds(to: NSSelectorFromString("accessibilityRole")) {
                if let role = object.accessibilityRole?(), [NSAccessibility.Role.button, .checkBox, .init(rawValue: "AXSwitch")].contains(role), let name = object.accessibilityLabel?() {
                    result[name] = element
                }
                for child in object.accessibilityChildren?() ?? [] { visit(child as AnyObject) }
            }
            if let view = object as? NSView { view.subviews.forEach(visit) }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        if let root = window.contentView { visit(root) }
        return result
    }

    @Test func barAndConversationButtonsDeliverTheirActions() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        fx.router.route(.requestAgent)
        let bar = try #require(fx.capture.window)
        try await Task.sleep(for: .milliseconds(200))
        let toggle = try #require(buttons(in: bar)["메모로 전환"])
        #expect(toggle.accessibilityPerformPress?() == true)
        #expect(fx.capture.mode == .memo)
        fx.capture.hide()
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let note = try fx.open("대상")
        fx.router.agent = agent
        fx.router.route(.openAgentWindow(note))
        let window = try #require(agent.window(for: note))
        defer { window.close() }
        let draft = try agent.record(for: note)
        var sends = 0
        agent.send = { _ in sends += 1 }
        let one = AgentConversation.Queued(text: "하나")
        draft.change { $0.draft = "글"; $0.queued = [one] }
        agent.performForVerification("hover", for: note)
        try await Task.sleep(for: .milliseconds(80))
        let items = buttons(in: window)
        for name in ["보내기", "고치기", "빼기", "지금 보내기"] { #expect(items[name] != nil) }
        let rects = try ["고치기", "빼기", "지금 보내기"].map { label in
            try #require(items[label]?.accessibilityFrame?())
        }
        #expect(rects.allSatisfy { $0.width == 20 && $0.height == 20 })
        #expect(rects[1].minX - rects[0].maxX == 2)
        #expect(rects[2].minX - rects[1].maxX == 2)
        #expect(items["보내기"]?.accessibilityPerformPress?() == true && sends == 1)
        #expect(items["고치기"]?.isAccessibilityEnabled?() == false)
        var selected: UUID?
        agent.sendNow = { _, id in selected = id }
        #expect(items["지금 보내기"]?.accessibilityPerformPress?() == true && selected == one.id)
        #expect(items["빼기"]?.accessibilityPerformPress?() == true && draft.conversation.queued.isEmpty)
    }
}

extension AgentButtonClickTests {
    @Test func historyLibraryCornerAndSettingsActions() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let note = try fx.open("대상")
        fx.router.agent = agent
        agent.present = fx.router.showAgent
        var trace: [String] = []
        fx.router.traceActivation = { trace.append($0) }
        var sends = 0
        agent.send = { _ in sends += 1 }
        let draft = try agent.record(for: note)
        var request = AgentRequest(id: UUID(), text: "회의", engine: "fixture", model: nil)
        request.status = .awaitingAnswer
        draft.change { $0.requests.append(request) }

        let library = LibraryCoordinator(theme: fx.theme, notes: fx.notes, spaces: fx.spaces, windows: fx.windowStates,
                                        preferences: try LibraryPreferencesStore(location: fx.location), router: fx.router)
        fx.router.connectHistory(library.model, agent: agent)
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        library.model.select(.conversations)
        library.model.previewSectionHover = true
        let lib = try #require(library.window)
        func press(_ name: String, in window: NSWindow) async throws {
            try await Task.sleep(for: .milliseconds(120))
            let button = try #require(buttons(in: window)[name], "버튼 \(name)")
            #expect(button.accessibilityPerformPress?() == true)
        }
        #expect(draft.conversation.seenAt == nil && trace.isEmpty)
        try await press("에이전트에게 요청", in: lib)
        #expect(fx.capture.mode == .request)
        fx.capture.hide()
        func findRow(_ view: NSView) -> HistoryRowInputView? {
            if let row = view as? HistoryRowInputView, row.id == draft.conversation.id { return row }
            return view.subviews.lazy.compactMap(findRow).first
        }
        let root = try #require(lib.contentView)
        root.layoutSubtreeIfNeeded()
        let row = try #require(findRow(root))
        let point = row.convert(.init(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        func click(_ count: Int) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: lib.windowNumber, context: nil,
                    eventNumber: 0, clickCount: count, pressure: 1))
                lib.sendEvent(event)
            }
        }
        try click(1)
        #expect(row.window === lib)
        #expect(library.model.selectedConversation == draft.conversation.id && draft.conversation.seenAt == nil)
        try click(2)
        try await Task.sleep(for: .milliseconds(120))
        #expect(draft.conversation.needsAnswer && draft.conversation.seenAt != nil)
        let panel = try #require(agent.window(for: note))
        try await press("지난 대화", in: panel)
        #expect(draft.showsHistory)
        try await press("회의", in: panel)
        #expect(!draft.showsHistory && agent.window(for: note) === panel)
        try await press("새 대화", in: panel)
        let fresh = try #require(agent.window(for: note))
        defer { fresh.close() }
        let freshDraft = try agent.record(for: note)
        #expect(panel !== fresh && freshDraft.conversation.requests.isEmpty)
        try await press("새 대화", in: lib)
        let global = try agent.record(for: nil)
        defer { agent.window(id: global.conversation.id)?.close() }
        let corner = AgentCorner(theme: fx.theme, agent: agent, router: fx.router, notes: fx.notePanels)
        corner.setEnabled(true)
        defer { corner.setEnabled(false) }
        let circle = try #require(corner.window)
        #expect(!circle.canBecomeKey && !circle.canBecomeMain)
        try await press("에이전트 열기", in: circle)
        defer { agent.window(id: draft.conversation.id)?.close() }
        #expect(trace == ["agent-open library", "agent-open clock", "agent-open new", "agent-open library-new", "agent-open corner"])
        #expect(sends == 0 && !lib.isKeyWindow)
        for screen in [CGRect(x: 0, y: 70, width: 1000, height: 650), CGRect(x: -1200, y: 10, width: 1200, height: 850)] {
            let frame = AgentCorner.circleFrame(visible: screen, diameter: 40, inset: 10)
            #expect(frame.maxX == screen.maxX - 10 && frame.minY == screen.minY + 10)
        }

        let store = try AppSettingsStore(stateDirectory: fx.location.stateDirectory)
        let old = try JSONDecoder().decode(SettingsValues.self, from: Data("{}".utf8))
        #expect(old.showsNoteAgent && !old.showsCornerAgent)
        let service = ScheduleService(notes: fx.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fx.location), read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fx.theme)
        settings.allowsKeyWindows = false
        settings.show(.assistant)
        defer { settings.window?.close() }
        let preferences = try #require(settings.window)
        for (label, noteOn, cornerOn) in [("화면 구석 단추", true, true), ("노트에 표시", false, true),
                                            ("화면 구석 단추", false, false), ("노트에 표시", true, false)] {
            try await press(label, in: preferences)
            let saved = try AppSettingsStore(stateDirectory: fx.location.stateDirectory).settings
            #expect(saved.showsNoteAgent == noteOn && saved.showsCornerAgent == cornerOn)
        }
        settings.show(.general)
        try await press("리마인더 있는 노트", in: preferences)
        try await press("마지막으로 본 곳에서 열기", in: preferences)
        let sidebar = try LibraryPreferencesStore(location: fx.location).value
        #expect(sidebar.visibleViews.contains(.reminders))
        #expect(!sidebar.opensLastSelection)
    }
}
