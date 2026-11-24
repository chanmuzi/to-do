import Agent
import AgentRunner
import Foundation
import Models
import Store
import Testing
@testable import FloatingNotes

@Suite struct AgentRequestQueueTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var store: AgentStore { AgentStore(location: .isolated(notesDirectory: root)) }
    func draft() -> AgentDraft { AgentDraft(.init(targets: []), store: store) }

    @Test func effortIsCapturedAtDispatch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let conversation = draft()
        var selection = AgentRequestCoordinator.Choice(provider: .claude, model: "opus", effort: "high")
        var efforts: [String?] = []
        let queue = AgentRequestCoordinator(choice: { selection }, note: { _ in nil }) { _, request, _ in
            efforts.append(request.effort)
            return "완료"
        }
        queue.submit(conversation, text: "처음")
        selection.effort = "low"
        queue.submit(conversation, text: "다음")
        while let task = queue.task { await task.value }
        #expect(efforts == ["high", "low"])
        #expect(conversation.conversation.requests.map(\.effort) == efforts)
    }

    @Test func orderedAcrossConversationsAndFailurePausesUntilRetry() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = draft(), b = draft()
        var calls: [String] = []
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, request, emit in
            calls.append(request.userText)
            emit(.started(model: nil))
            if calls.count == 1 { throw AgentError.providerFailure }
            return "답"
        }
        queue.submit(a, text: "첫째")
        queue.submit(b, text: "둘째")
        queue.submit(a, text: "셋째")
        queue.submit(b, text: "고치기")
        queue.submit(a, text: "빼기")
        b.update("초안")
        let edit = try #require(b.conversation.queued.last?.id)
        b.remove(edit, editing: true)
        #expect(b.conversation.draft == "초안" && b.conversation.queued.count == 2)
        b.update("")
        b.remove(edit, editing: true)
        #expect(b.conversation.draft == "고치기" && b.conversation.queued.count == 1)
        a.remove(try #require(a.conversation.queued.last?.id), editing: false)
        await queue.task?.value
        #expect(calls == ["첫째"])
        let previous = try #require(a.conversation.requests.first)
        #expect(previous.status == .failed)
        queue.retry(a, id: previous.id)
        queue.retry(a, id: previous.id)
        while let task = queue.task { await task.value }
        #expect(calls == ["첫째", "첫째", "둘째", "셋째"])
        #expect(a.conversation.requests.first?.runID != previous.runID)
        #expect(a.conversation.messages.filter { $0.requestID == previous.id }.count == 2)
        #expect(a.conversation.queued.isEmpty && b.conversation.queued.isEmpty)
    }

    @Test func newSendAfterFailureWithEmptyQueueStartsWithoutReplayingFailure() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = draft(), b = draft()
        var calls: [String] = []
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, request, _ in
            calls.append(request.userText)
            if calls.count == 1 { throw AgentError.providerFailure }
            return "답"
        }
        queue.submit(a, text: "실패")
        await queue.task?.value
        queue.submit(b, text: "새 요청")
        await queue.task?.value
        #expect(calls == ["실패", "새 요청"])
        #expect(b.conversation.requests.last?.status == .completed)
    }

    @Test func seeingQuestionPreservesOrderAndOnlyItsNextTurnResolvesIt() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = draft(), b = draft()
        var question = AgentRequest(id: UUID(), text: "확인", engine: "fixture", model: nil)
        question.status = .awaitingAnswer
        a.change { $0.requests.append(question) }
        let date = a.conversation.updatedAt
        a.markSeen()
        #expect(a.conversation.updatedAt == date && a.conversation.needsAnswer)
        let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }) { _, _, _ in "답" }
        queue.submit(b, text: "다른 대화")
        queue.submit(a, text: "확인했습니다")
        #expect(a.conversation.needsAnswer)
        while let active = queue.task { await active.value }
        let saved = try #require(store.loadConversations { Issue.record("\($0)") }.first { $0.id == a.conversation.id })
        #expect(!saved.needsAnswer && saved.seenAt != nil && saved.requests.count == 2)
    }

    @Test func shutdownMakesOneRetryReservation() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let a = draft()
        let queue = AgentRequestCoordinator(choice: { .init(provider: .codex, model: nil) }, note: { _ in nil }) { _, _, _ in
            try await Task.sleep(for: .seconds(3))
            return "답"
        }
        queue.submit(a, text: "첫 요청")
        queue.submit(a, text: "다음 요청")
        await queue.shutdown()
        let saved = try #require(store.loadConversations { Issue.record("\($0)") }.first)
        #expect(saved.requests.first?.stopReason == .shutdown)
        #expect(saved.queued.map(\.text) == ["첫 요청", "다음 요청"])
        #expect(saved.queued.first?.id == saved.requests.first?.id)
    }

    @Test(arguments: [AgentProvider.claude, .codex])
    func sendNowReapsOldGroupBeforeNextProcess(_ provider: AgentProvider) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let initLine = #"{"type":"system","subtype":"init","tools":["mcp__float__list_notes","mcp__float__read_note","mcp__float__propose_change"],"mcp_servers":[{"name":"float","status":"connected"}],"skills":[],"slash_commands":[],"plugins":[],"model":"test"}"#
        let output = provider == .claude ? """
        echo '\(initLine)'
        echo '{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"부분"}}}'
        """ : """
        echo '{"type":"thread.started"}'
        echo '{"type":"item.completed","item":{"type":"agent_message","id":"1","text":"부분"}}'
        """
        let ending = provider == .claude ? #"{"type":"result","is_error":false,"subtype":"success","result":"완료"}"# : #"{"type":"turn.completed"}"#
        let body = """
        #!/bin/sh
        set -eu
        bin=\(bin.path)
        case "$1" in
            --version) echo 'test 1.0'; exit 0;;
            auth) echo '{"loggedIn":true}'; exit 0;;
            login) echo 'Logged in using ChatGPT'; exit 0;;
        esac
        if test -f "$bin/pid" && kill -0 "$(cat "$bin/pid")" 2>/dev/null; then exit 97; fi
        \(output)
        if test ! -e "$bin/pid"; then sleep 60 & echo $! > "$bin/pid"; wait; fi
        echo '\(ending)'
        """
        for name in [provider.rawValue, "node"] {
            let file = bin.appending(path: name)
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        let execution = AgentExecution(location: location, directory: bin, server: bin.appending(path: "FloatMCP"))
        let q = AgentRequestCoordinator(choice: { .init(provider: provider, model: nil) }, note: { _ in nil }, execute: execution.run)
        let a = draft(), b = draft()
        q.submit(a, text: "원래")
        for _ in 0..<500 where a.conversation.requests.first?.answer != "부분" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(a.conversation.requests.first?.answer == "부분")
        q.submit(b, text: "차례")
        q.submit(a, text: "선택")
        let chosen = try #require(a.conversation.queued.first?.id)
        q.sendNow(a, id: chosen)
        q.sendNow(a, id: chosen)
        while let task = q.task { await task.value }
        let stopped = try #require(a.conversation.requests.first)
        #expect(stopped.status == .interrupted && stopped.answer == "부분" && !stopped.steps.isEmpty)
        #expect(a.conversation.requests.map(\.userText) == ["원래", "선택"])
        #expect(a.conversation.requests.last?.status == .completed && b.conversation.requests.first?.status == .completed)
        let records = location.stateDirectory.appending(path: "agent-usage")
        #expect(try FileManager.default.contentsOfDirectory(atPath: records.path).count == 3)
        let data = try Data(contentsOf: records.appending(path: stopped.runID.uuidString + ".json"))
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["outcome"] as? String == "cancelled")
        #expect(Set(fields.keys).isSubset(of: ["outcome","actualModel","requestedModel","provider","usage","elapsedSeconds","startedAt"]))
        #expect(try store.loadConversations { Issue.record("\($0)") }.contains(a.conversation))
    }
}
