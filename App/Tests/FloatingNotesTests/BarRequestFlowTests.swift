import Agent
import AgentRunner
import AppKit
import Models
import Store
import Testing
import Theme
@testable import FloatingNotes

@MainActor struct BarRequestFlowTests {
    @Test func newChatsShareThePanelAndQueueAndRememberOnlyTheLastBarQuestion() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let store = AgentStore(location: fx.location)
        let agent = AgentWindowCoordinator(store: store, theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, _, emit in
            emit(.text("**첫 줄**"))
            return "**첫 줄**\n- 둘째 줄\n셋째 줄"
        }
        let bar = BarRequestFlow(agent: agent, requests: queue)
        let a = try #require(bar.submit("원래 물음"))
        a.update("쓰던 초안")
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 800)
        let frame = CGRect(x: 52, y: 480, width: 340, height: 218)
        agent.open(record: a, title: "", frame: frame, visible: bounds, reuseForBar: true)
        let window = try #require(agent.window(id: a.conversation.id))
        defer { window.close() }
        let b = try #require(bar.submit("다음 물음"))
        #expect(a !== b && a.conversation.requests.first?.status == .running)
        #expect(b.conversation.queued.map(\.text) == ["다음 물음"])
        #expect(bar.recent?.detail == "차례를 기다리는 중")
        agent.open(record: b, title: "", frame: frame, visible: bounds, reuseForBar: true)
        #expect(agent.window(id: b.conversation.id) === window && agent.window(id: a.conversation.id) == nil)
        #expect(a.conversation.draft == "쓰던 초안" && agent.history.count == 2)
        while let task = queue.task { await task.value }
        #expect(bar.recent?.question == "다음 물음" && bar.recent?.detail == "첫 줄")
        var notices: [AgentReplyNotification] = []
        bar.deliver = { notices.append($0); return true }
        let first = try #require(a.conversation.requests.first)
        await bar.finished(a, first)?.value
        #expect(notices.map(\.body) == ["첫 줄\n둘째 줄"])
        #expect(notices.first?.conversation == a.conversation.id && notices.first?.title == "원래 물음")
        let restored = AgentWindowCoordinator(store: store, theme: fx.theme) { Issue.record("\($0)") }
        try restored.restore()
        #expect(restored.recentBar?.conversation.id == b.conversation.id)
        #expect(restored.record(id: a.conversation.id)?.conversation.draft == "쓰던 초안")
        try await agent.delete(b)
        #expect(bar.recent == nil && agent.history.count == 1)
        let afterDeletion = AgentWindowCoordinator(store: store, theme: fx.theme) { Issue.record("\($0)") }
        try afterDeletion.restore()
        #expect(afterDeletion.recentBar == nil && afterDeletion.history.count == 1)
    }

    @Test func closedWindowFailureAndDeniedNotifications() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let agent = AgentWindowCoordinator(store: .init(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, _, _ in
            throw AgentRequestCoordinator.Failure(message: "연결을 확인해 주세요", settings: true)
        }
        let bar = BarRequestFlow(agent: agent, requests: queue)
        let draft = try #require(bar.submit("물음"))
        queue.openSettings = { _ in Issue.record("막대 요청 실패는 대화 창에서 처리해야 합니다") }
        await queue.task?.value
        let request = try #require(draft.conversation.requests.first)
        var logs: [String] = []
        bar.log = { logs.append($0) }
        bar.deliver = { payload in
            #expect(payload.body == "연결을 확인해 주세요" && payload.request == request.id)
            return false
        }
        bar.showsConversation = { $0 == draft.conversation.id }
        #expect(bar.finished(draft, request) == nil && logs.isEmpty)
        bar.showsConversation = { _ in false }
        await bar.finished(draft, request)?.value
        #expect(logs.count == 1 && bar.recent?.face == .blocked)
    }
}
