import Agent
import AgentRunner
import Foundation
import Models

/// 대화 파일의 줄은 보존한다. 이번 실행에서 사용자가 보낸 항목만 자동 전송 후보가 된다.
final class AgentRequestCoordinator {
    struct Choice {
        var provider: AgentProvider
        var model: String?
    }
    struct Failure: Error {
        let message: String
        var settings = false
        var resumeAt: Date?
    }
    typealias Execute = (AgentConversation, AgentRequest, @escaping @Sendable (AgentEvent) -> Void) async throws -> String
    private struct Entry {
        let draft: AgentDraft
        let id: UUID
    }
    private let choice: () -> Choice
    private let execute: Execute
    private let note: (String) -> (NoteID, String)?
    var progress: (AgentRequest) -> Void = { _ in }
    var finished: (AgentDraft, AgentRequest) -> Void = { _, _ in }
    var openSettings: (String) -> Void = { _ in }
    private var order: [Entry] = []
    private var activeDraft: AgentDraft?
    private var isolationFailed = false
    private var priority: Entry?
    private var paused = false
    private var closing = false
    private(set) var task: Task<Void, Never>?

    init(choice: @escaping () -> Choice, note: @escaping (String) -> (NoteID, String)?,
         execute: @escaping Execute) {
        self.choice = choice
        self.note = note
        self.execute = execute
    }

    @discardableResult func submit(_ draft: AgentDraft, text: String, fromInput: Bool = true) -> Bool {
        guard !closing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        prune()
        if task == nil && order.isEmpty { paused = false; draft.queueHeld = false }
        let item = AgentConversation.Queued(text: text, held: paused)
        if paused { draft.queueHeld = true }
        guard draft.change({
            $0.queued.append(item)
            if fromInput { $0.draft = "" }
        }) else { return false }
        order.append(Entry(draft: draft, id: item.id))
        advance()
        return true
    }

    private func prune() {
        order.removeAll { entry in !entry.draft.conversation.queued.contains { $0.id == entry.id } }
    }

    private func hold(_ drafts: [AgentDraft], afterFailure: Bool) {
        var seen = Set<UUID>()
        for draft in drafts where seen.insert(draft.conversation.id).inserted {
            draft.queueHeld = true
            if afterFailure {
                draft.change { value in
                    for i in value.queued.indices { value.queued[i].heldAfterFailure = true }
                }
            }
        }
    }

    private func release(_ draft: AgentDraft) {
        guard draft.change({ value in
            for i in value.queued.indices { value.queued[i].heldAfterFailure = false }
        }) else { return }
        draft.queueHeld = false
    }

    func sendAll(_ draft: AgentDraft) {
        guard !closing, !draft.conversation.queued.isEmpty else { return }
        release(draft)
        paused = false
        advance()
    }

    func sendNow(_ draft: AgentDraft, id: UUID) {
        guard !closing, priority == nil, draft.conversation.queued.contains(where: { $0.id == id }) else { return }
        priority = Entry(draft: draft, id: id)
        paused = false
        if let task { task.cancel() } else { advance() }
    }

    func retry(_ draft: AgentDraft, id: UUID) {
        guard !closing, task == nil, let previous = draft.conversation.requests.first(where: { $0.id == id }),
              [.failed, .interrupted].contains(previous.status) else { return }
        let selection = choice()
        let request = AgentRequest(id: id, text: previous.userText, engine: selection.provider.rawValue, model: selection.model)
        guard draft.change({ value in
            if let index = value.requests.firstIndex(where: { $0.id == id }) { value.requests[index] = request }
            value.messages.removeAll { $0.requestID == id && $0.role == .assistant }
        }) else { return }
        for entry in order where entry.draft.queueHeld { release(entry.draft) }
        paused = false
        start(draft, request)
    }

    private func advance() {
        guard !closing, task == nil, !paused else { return }
        let expedited = priority?.id
        if let entry = priority {
            priority = nil
            order.removeAll { $0.id == entry.id }
            order.insert(entry, at: 0)
        }
        while let index = order.firstIndex(where: { !$0.draft.queueHeld || $0.id == expedited }) {
            let entry = order[index]
            let draft = entry.draft
            guard let item = draft.conversation.queued.first(where: { $0.id == entry.id }) else {
                order.remove(at: index)
                continue
            }
            let selection = choice()
            let request = AgentRequest(id: item.id, text: item.text, engine: selection.provider.rawValue, model: selection.model)
            guard draft.change({
                $0.queued.removeAll { $0.id == item.id }
                for index in $0.requests.indices where $0.requests[index].status == .awaitingAnswer {
                    $0.requests[index].status = .completed
                }
                $0.requests.append(request)
                $0.messages.append(.init(role: .user, requestID: item.id, text: item.text))
            }) else { paused = true; return }
            order.remove(at: index)
            start(draft, request)
            return
        }
    }

    private func start(_ draft: AgentDraft, _ request: AgentRequest) {
        activeDraft = draft
        let snapshot = draft.conversation
        task = Task {
            let (events, continuation) = AsyncStream<AgentEvent>.makeStream()
            let consumer = Task {
                var files: [String: String] = [:]
                for await event in events {
                    guard let i = draft.conversation.requests.firstIndex(where: { $0.runID == request.runID }) else { continue }
                    let before = draft.conversation.requests[i].steps.last?.kind
                    apply(event, to: &draft.conversation.requests[i], files: &files)
                    if before != draft.conversation.requests[i].steps.last?.kind { progress(draft.conversation.requests[i]) }
                    if case .toolEnded = event { draft.save() }
                }
            }
            let result: Result<String, Error>
            do {
                let answer = try await execute(snapshot, request) { continuation.yield($0) }
                try Task.checkCancellation()
                result = .success(answer)
            } catch { result = .failure(error) }
            continuation.finish()
            await consumer.value
            finish(result, draft: draft, request: request)
        }
    }

    private func apply(_ event: AgentEvent, to request: inout AgentRequest, files: inout [String: String]) {
        func begin(_ kind: AgentRequest.Step.Kind, id: String? = nil) {
            let now = Date()
            if let i = request.steps.indices.last, request.steps[i].callID == nil {
                end(&request.steps[i], now: now)
            }
            request.steps.append(.init(kind, callID: id, now: now))
        }
        switch event {
        case .started: begin(.think)
        case .text(let text):
            if request.steps.last?.kind != .write { begin(.write) }
            request.answer = (request.answer ?? "") + text
        case .tool(let name): begin(name.hasSuffix("read_note") ? .read : .search)
        case let .toolStarted(id, name, file):
            if request.steps.contains(where: { $0.callID == id }) { return }
            begin(name == "read_note" ? .read : .search, id: id)
            if name == "read_note" { files[id] = file }
        case let .toolEnded(id, succeeded):
            guard let i = request.steps.firstIndex(where: { $0.callID == id && $0.endedAt == nil }) else { return }
            let file = files.removeValue(forKey: id)
            if succeeded, let file, let (id, title) = note(file) {
                request.steps[i].noteID = id
                request.steps[i].noteTitle = title
            }
            request.steps[i].result = succeeded ? "완료" : "실패"
            end(&request.steps[i], now: Date())
        case .rateLimit, .usage: break
        }
    }

    private func end(_ step: inout AgentRequest.Step, now: Date) {
        guard step.endedAt == nil else { return }
        step.endedAt = now
        step.elapsed = max(0, now.timeIntervalSince(step.startedAt))
    }

    private func finish(_ result: Result<String, Error>, draft: AgentDraft, request: AgentRequest) {
        guard let i = draft.conversation.requests.firstIndex(where: { $0.runID == request.runID }) else { return }
        var final = draft.conversation.requests[i]
        for j in final.steps.indices { end(&final.steps[j], now: Date()) }
        var settings = false
        switch result {
        case .success(let answer):
            final.answer = answer
            final.status = .completed
        case .failure(let error):
            let groupFailure = (error as? AgentError) == .isolation("process_group")
            if groupFailure { priority = nil; closing = true; isolationFailed = true }
            let interrupted = !groupFailure && (Task.isCancelled || error is CancellationError)
            final.status = interrupted ? .interrupted : .failed
            if !interrupted {
                let failure = error as? Failure
                final.failure = failure?.message ?? "요청을 마치지 못했어요"
                final.resumeAt = failure?.resumeAt
                settings = failure?.settings == true
            }
            paused = priority == nil
        }
        draft.conversation.requests[i] = final
        if let text = final.answer, !text.isEmpty {
            draft.conversation.messages.append(.init(role: .assistant, requestID: final.id, text: text))
        }
        draft.conversation.updatedAt = Date()
        draft.save()
        activeDraft = nil
        task = nil
        if draft.deleting { return }
        guard draft.writeError == nil else { paused = true; return }
        if !closing {
            if paused { hold(order.map(\.draft), afterFailure: final.status == .failed) }
            if final.status != .interrupted { finished(draft, final) }
            if settings { openSettings(final.engine) }
            advance()
        }
    }

    func stopBeforeDelete(_ draft: AgentDraft) async throws {
        if activeDraft === draft, let active = task {
            active.cancel()
            await active.value
        }
        guard !isolationFailed else { throw AgentError.isolation("process_group") }
        if priority?.draft === draft { priority = nil }
        order.removeAll { $0.draft === draft }
        if !paused || draft.conversation.requests.last?.status == .interrupted {
            paused = false
            advance()
        }
    }

    func continueAfterCancelledQuit() { closing = false }

    func shutdown() async {
        closing = true
        let active = task
        active?.cancel()
        await active?.value
    }
}
