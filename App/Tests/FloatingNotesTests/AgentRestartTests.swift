import Agent
import AgentRunner
import Foundation
import Models
import Store
import Testing
import Theme
@testable import FloatingNotes

@Suite struct AgentRestartTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var store: AgentStore { AgentStore(location: .isolated(notesDirectory: root)) }
    func catalog() throws -> AgentWindowCoordinator {
        let catalog = AgentWindowCoordinator(store: store, theme: try Theme.bundled()) { Issue.record("\($0)") }
        try catalog.restore()
        return catalog
    }
    func queue(_ run: @escaping AgentRequestCoordinator.Execute) -> AgentRequestCoordinator {
        AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }, execute: run)
    }

    @Test func completionAndConversationNameUseTheFirstVisibleMarkdownLine() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var notices: [AgentReplyNotification] = []
        let replies = AgentReplyNotifications(showsConversation: { _ in false }, deliver: { notices.append($0); return true })
        var conversation = AgentConversation(targets: [])
        let prompt = "\n---\n- [x] *오늘* [일정](https://example.com)과 `할 일`"
        conversation.queued = [.init(text: prompt)]
        #expect(conversation.name == "오늘 일정과 할 일")
        var request = AgentRequest(id: UUID(), text: prompt, engine: "fixture", model: nil)
        request.status = .completed
        request.answer = "  \n---\n# 노트를 확인했지만, **오늘 할 일은 없어요.**\n다음 줄"
        conversation.requests = [request]
        let draft = AgentDraft(conversation, store: store)
        await replies.finished(draft, request)?.value
        #expect(notices.last?.body == "노트를 확인했지만, 오늘 할 일은 없어요.\n다음 줄")
        let restored = try JSONDecoder().decode(AgentConversation.self, from: JSONEncoder().encode(conversation))
        #expect(restored.name == "오늘 일정과 할 일")
        #expect(restored.requests.first?.userText == prompt)
        request.answer = "---\n- [ ]\n##"
        await replies.finished(draft, request)?.value
        #expect(notices.last?.body == "끝났어요")
        request.answer = "1. `*literal*`와 _기울임_"
        await replies.finished(draft, request)?.value
        #expect(notices.last?.body == "*literal*와 기울임")
        conversation.customName = "내 *이름*"
        #expect(conversation.name == "내 *이름*")
        draft.change { $0.customName = conversation.customName }
        await replies.finished(draft, request)?.value
        #expect(notices.last?.title == "오늘 일정과 할 일" && notices.last?.body == "*literal*와 기울임")
    }

    @Test func crashAndRepeatedShutdownKeepOneBubbleAndGlobalOrder() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try catalog()
        let a = original.newRecord(), b = original.newRecord()
        let originalRun = AgentRequest(id: UUID(), text: "하나", engine: "codex", model: "fixture")
        a.change {
            $0.requests = [originalRun]
            $0.messages = [.init(role: .user, requestID: originalRun.id, text: originalRun.userText)]
            $0.queued = [.init(text: "셋", order: 12)]
        }
        b.change { $0.queued = [.init(text: "둘", order: 11), .init(text: "넷", order: 13)] }
        let restarted = try catalog()
        let middle = queue { _, _, _ in try await Task.sleep(for: .seconds(5)); return "" }
        middle.restore(restarted.drafts)
        await middle.shutdown()
        let next = try catalog()
        var calls: [String] = []
        let final = queue { _, request, _ in calls.append(request.userText); return "완료" }
        var notices: [AgentReplyNotification] = []
        var deliveries: [Task<Void, Never>] = []
        let replies = AgentReplyNotifications(showsConversation: next.showsConversation, deliver: { notices.append($0); return true })
        final.finished = { if let task = replies.finished($0, $1) { deliveries.append(task) } }
        final.restore(next.drafts)
        final.restore(next.drafts)
        while let active = final.task { await active.value }
        for delivery in deliveries { await delivery.value }
        #expect(notices.map(\.title) == calls && notices.allSatisfy { $0.body == "완료" })
        #expect(next.window(id: a.conversation.id) == nil && next.window(id: b.conversation.id) == nil)
        #expect(calls == ["하나", "둘", "셋", "넷"])
        let value = try #require(next.record(id: a.conversation.id)?.conversation)
        let first = try #require(value.requests.first)
        #expect(first.id == originalRun.id && first.engine == "codex" && first.model == "fixture")
        #expect(first.stoppedAttempts?.count == 2 && first.stoppedAttempts?.first?.id == originalRun.runID)
        #expect(value.messages.filter { $0.role == .user && $0.requestID == first.id }.count == 1)
    }

    @Test func unavailableStartupIsSilentAndCanBeRemovedOrSent() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var calls = 0, probes = 0, completions = 0
        let a = AgentDraft(.init(targets: []), store: store), b = AgentDraft(.init(targets: []), store: store)
        a.change { $0.queued = [.init(text: "하나", order: 1)] }
        b.change { $0.queued = [.init(text: "둘", order: 2)] }
        let q = queue { _, _, _ in calls += 1; return "답" }
        q.prepareRecovery = { _ in probes += 1; return nil }
        q.finished = { _, _ in completions += 1 }
        q.restore([b, a])
        while let active = q.task { await active.value }
        #expect(probes == 1 && calls == 0 && completions == 0)
        #expect(a.queueHeld && b.queueHeld)
        a.change { $0.queued.removeAll() }
        q.sendAll(b)
        while let active = q.task { await active.value }
        #expect(calls == 1 && completions == 1 && a.conversation.requests.isEmpty)
    }

    @Test func failedQueuesAndUserInterruptionsStayPutAcrossLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try catalog()
        let a = old.newRecord(), b = old.newRecord()
        let q = queue { _, _, _ in throw AgentError.providerFailure }
        q.submit(a, text: "실패")
        q.submit(b, text: "다음")
        await q.task?.value
        let c = old.newRecord()
        c.change {
            var request = AgentRequest(id: UUID(), text: "중단", engine: "claude", model: nil)
            request.status = .interrupted
            request.stopReason = .user
            $0.requests = [request]
        }
        let next = try catalog()
        var calls: [String] = []
        let newQueue = queue { _, request, _ in calls.append(request.userText); return "완료" }
        newQueue.restore(next.drafts)
        let waiting = try #require(next.record(id: b.conversation.id))
        #expect(newQueue.task == nil && waiting.queueHeld && calls.isEmpty)
        newQueue.sendAll(waiting)
        await newQueue.task?.value
        #expect(calls == ["다음"])
    }

    @Test(arguments: [true, false])
    func previousFailureHoldsAnotherFileEvenBeforeItsQueueWasMarked(_ legacy: Bool) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = AgentDraft(.init(targets: []), store: store), b = AgentDraft(.init(targets: []), store: store)
        a.change {
            var request = AgentRequest(id: UUID(), text: "실패", engine: "fixture", model: nil)
            request.status = .failed
            request.failedThroughOrder = legacy ? nil : 8
            $0.requests = [request]
        }
        b.change { $0.queued = [.init(text: "남은 차례", order: legacy ? nil : 8)] }
        let restored = try catalog()
        let q = queue { _, _, _ in Issue.record("멈춘 줄 전송"); return "" }
        q.restore(restored.drafts)
        #expect(q.task == nil && restored.record(id: b.conversation.id)?.queueHeld == true)
    }

    @Test func deleteWaitsForCancellationAndContinuesOtherConversation() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let windows = try catalog()
        let a = windows.newRecord(), b = windows.newRecord()
        var reaped = false
        let q = queue { value, _, _ in
            if value.id == a.conversation.id {
                defer { reaped = true }
                try await Task.sleep(for: .seconds(10))
            } else { #expect(reaped) }
            return "답"
        }
        windows.stopBeforeDelete = q.stopBeforeDelete
        windows.finishDeletion = q.finishDeletion
        q.submit(a, text: "실행")
        q.submit(a, text: "함께 지움")
        q.submit(b, text: "남김")
        try await windows.delete(a)
        while let active = q.task { await active.value }
        #expect(reaped && windows.record(id: a.conversation.id) == nil)
        #expect(b.conversation.requests.last?.status == .completed)
        a.update("닫힌 창")
        #expect(try store.loadConversations { Issue.record("\($0)") }.map(\.id) == [b.conversation.id])
    }
}
