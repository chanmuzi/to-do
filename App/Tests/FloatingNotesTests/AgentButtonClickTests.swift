import Agent
import AppKit
@_spi(Verification) import Capture
import Models
import Store
import Testing
@testable import FloatingNotes

@Suite @MainActor struct AgentButtonClickTests {
    private func buttons(in window: NSWindow) -> [String: AnyObject] {
        var result: [String: AnyObject] = [:]
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: AnyObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let element = object as? NSObject, element.responds(to: NSSelectorFromString("accessibilityRole")) {
                if object.accessibilityRole?() == .button, let name = object.accessibilityLabel?() {
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
        NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
        defer { NSApp.accessibilitySetValue(false, forAttribute: .init(rawValue: "AXEnhancedUserInterface")) }
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
