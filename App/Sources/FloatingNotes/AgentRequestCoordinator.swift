import Agent
import AgentRunner
import Foundation
import Models
import Store

/// 모든 대화의 실행과 연결 확인을 한 자리에서 직렬화한다.
final class AgentRequestCoordinator {
    struct Choice {
        var provider: AgentProvider
        var model: String?
        var effort: String?
    }
    struct Failure: Error {
        let message: String
        var resumeAt: Date?
    }
    typealias Execute = (AgentConversation, AgentRequest, @escaping @Sendable (AgentEvent) -> Void) async throws -> String
    private struct Entry {
        let draft: AgentDraft
        let id: UUID
        var automatic = false
    }
    private let choice: () -> Choice
    private let execute: Execute
    private let note: (String) -> (NoteID, String)?
    var inbox: ProposalInbox?
    var finished: (AgentDraft, AgentRequest) -> Void = { _, _ in }
    private var order: [Entry] = []
    private var activeDraft: AgentDraft?
    private var isolationFailed = false
    private var priority: Entry?
    private var paused = false
    private var failedQueue = false
    private var restored = false
    private var lastOrder: Int64 = 0
    private var stoppingForShutdown = false
    var prepareRecovery: ((Choice) async -> Execute?)?
    private var closing = false
    private(set) var task: Task<Void, Never>?

    init(choice: @escaping () -> Choice, note: @escaping (String) -> (NoteID, String)?,
         execute: @escaping Execute) {
        self.choice = choice
        self.note = note
        self.execute = execute
    }

    func restore(_ drafts: [AgentDraft]) {
        guard !restored else { return }
        restored = true
        // 옛 파일은 대화 사이의 전송 순서가 없다. 활동 시각, 파일 ID, 파일 안의 순서로 복원한다.
        let records = drafts.sorted {
            ($0.conversation.updatedAt, $0.conversation.id.uuidString) < ($1.conversation.updatedAt, $1.conversation.id.uuidString)
        }
        // 실패 기록을 먼저 저장하고 다른 파일의 줄을 표시하는 사이에 종료돼도 그 차례를 보존한다.
        let failureBoundary = records.flatMap { $0.conversation.requests }.compactMap(\.failedThroughOrder).max() ?? 0
        let legacyPaused = records.compactMap { $0.conversation.requests.last }.last?.status == .failed
        lastOrder = failureBoundary
        var entries: [(Int64, Entry)] = []
        for draft in records {
            let value = draft.conversation
            for item in value.queued {
                lastOrder = max(lastOrder, item.order ?? 0)
                entries.append((item.order ?? 1, Entry(draft: draft, id: item.id, automatic: true)))
                let coveredByFailure = item.order.map { $0 > 0 && $0 <= failureBoundary } ?? legacyPaused
                if item.heldAfterFailure ?? coveredByFailure { draft.queueHeld = true }
            }
        }
        failedQueue = records.contains { $0.queueHeld }
        order = entries.sorted { $0.0 < $1.0 }.map(\.1)
        paused = !order.isEmpty && order.allSatisfy { $0.draft.queueHeld }
        advance()
    }

    @discardableResult func submit(_ draft: AgentDraft, text: String, fromInput: Bool = true, fromBar: Bool = false) -> Bool {
        guard !closing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        prune()
        if task == nil && order.isEmpty { paused = false; failedQueue = false; draft.queueHeld = false }
        lastOrder += 1
        let item = AgentConversation.Queued(text: text, order: lastOrder, held: failedQueue && (paused || draft.queueHeld) ? true : nil)
        if paused { draft.queueHeld = true }
        guard draft.change({
            if fromBar { $0.barRequestID = item.id }
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
        for i in order.indices where order[i].draft === draft { order[i].automatic = false }
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
              previous.status == .failed else { return }
        let selection = choice()
        var request = AgentRequest(id: id, text: previous.userText, engine: selection.provider.rawValue, model: selection.model, effort: selection.effort)
        request.stoppedAttempts = previous.stoppedAttempts
        guard draft.change({ value in
            if let index = value.requests.firstIndex(where: { $0.id == id }) { value.requests[index] = request }
            value.messages.removeAll { $0.requestID == id && $0.role == .assistant }
        }) else { return }
        for entry in order where entry.draft.queueHeld { release(entry.draft) }
        paused = false
        start(draft, request, execute: execute)
    }

    private func advance() {
        guard !closing, task == nil, !paused else { return }
        let expedited = priority?.id
        if let entry = priority {
            priority = nil
            order.removeAll { $0.id == entry.id }
            order.insert(entry, at: 0)
        }
        prune()
        guard let entry = order.first(where: { !$0.draft.deleting && (!$0.draft.queueHeld || $0.id == expedited) }) else { return }
        var selection = choice()
        if let previous = entry.draft.conversation.requests.first(where: { $0.id == entry.id }),
           let provider = AgentProvider(rawValue: previous.engine) {
            selection = Choice(provider: provider, model: previous.model, effort: previous.effort)
        }
        if entry.automatic, let prepareRecovery {
            activeDraft = entry.draft
            task = Task {
                let prepared = await prepareRecovery(selection)
                task = nil
                activeDraft = nil
                guard !closing, !entry.draft.deleting else { return }
                guard !Task.isCancelled else { advance(); return }
                guard let prepared else {
                    paused = true
                    hold(order.map(\.draft), afterFailure: false)
                    return
                }
                dispatch(entry, selection: selection, execute: prepared)
            }
        } else {
            dispatch(entry, selection: selection, execute: execute)
        }
    }

    private func dispatch(_ entry: Entry, selection: Choice, execute: @escaping Execute) {
        let draft = entry.draft
        guard let item = draft.conversation.queued.first(where: { $0.id == entry.id }) else { advance(); return }
        var request = AgentRequest(id: item.id, text: item.text, engine: selection.provider.rawValue, model: selection.model, effort: selection.effort)
        guard draft.change({ value in
            value.queued.removeAll { $0.id == item.id }
            for index in value.requests.indices where value.requests[index].status == .awaitingAnswer {
                value.requests[index].status = .completed
            }
            if let index = value.requests.firstIndex(where: { $0.id == item.id }) {
                let previous = value.requests[index]
                request.stoppedAttempts = (previous.stoppedAttempts ?? []) + [.init(previous)]
                value.requests[index] = request
                value.messages.removeAll { $0.requestID == item.id && $0.role == .assistant }
            } else {
                value.requests.append(request)
                value.messages.append(.init(role: .user, requestID: item.id, text: item.text))
            }
        }) else { paused = true; hold([draft], afterFailure: false); return }
        order.removeAll { $0.id == entry.id }
        start(draft, request, execute: execute)
    }

    private func start(_ draft: AgentDraft, _ request: AgentRequest, execute: @escaping Execute) {
        activeDraft = draft
        let snapshot = draft.conversation
        task = Task {
            let (events, continuation) = AsyncStream<AgentEvent>.makeStream()
            let consumer = Task {
                var files: [String: String] = [:]
                for await event in events {
                    guard let i = draft.conversation.requests.firstIndex(where: { $0.runID == request.runID }) else { continue }
                    apply(event, to: &draft.conversation.requests[i], files: &files)
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
        case .tool(let name): begin(name.hasSuffix("propose_change") ? .write : name.hasSuffix("read_note") ? .read : .search)
        case let .toolStarted(id, name, file):
            if request.steps.contains(where: { $0.callID == id }) { return }
            begin(name == "propose_change" ? .write : name == "read_note" ? .read : .search, id: id)
            if name == "read_note", let file {
                files[id] = file
                request.steps[request.steps.count - 1].noteTitle = note(file)?.1
            }
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
        let completed = result.flatMap { answer in
            Result {
                try Task.checkCancellation()
                final.proposals = try inbox?.proposals(for: request, source: draft.conversation.targets.first) ?? []
                return answer
            }
        }
        switch completed {
        case .success(let answer):
            final.answer = answer
            final.status = .completed
        case .failure(let error):
            let groupFailure = (error as? AgentError) == .isolation("process_group")
            if groupFailure { priority = nil; closing = true; isolationFailed = true }
            let interrupted = !groupFailure && (Task.isCancelled || error is CancellationError)
            final.status = interrupted ? .interrupted : .failed
            if interrupted { final.stopReason = stoppingForShutdown ? .shutdown : .user }
            if !interrupted {
                final.failedThroughOrder = lastOrder
                let failure = error as? Failure
                final.failure = failure?.message ?? "요청을 마치지 못했어요"
                final.resumeAt = failure?.resumeAt
            }
            paused = priority == nil
        }
        let finishedAt = Date()
        for index in final.steps.indices where final.steps[index].endedAt == nil {
            if final.status == .interrupted { final.steps[index].result = "중단" }
            if final.status == .failed { final.steps[index].result = "실패" }
            end(&final.steps[index], now: finishedAt)
        }
        draft.conversation.requests[i] = final
        if final.stopReason == .shutdown { draft.conversation.interruptForShutdown(at: i) }
        if let text = final.answer, !text.isEmpty {
            draft.conversation.messages.append(.init(role: .assistant, requestID: final.id, text: text))
        }
        draft.conversation.updatedAt = Date()
        draft.save()
        if draft.writeError == nil || final.status != .completed {
            do { try inbox?.remove(request.runID) }
            catch { draft.writeError = error }
        }
        activeDraft = nil
        task = nil
        if draft.deleting { return }
        guard draft.writeError == nil else { paused = true; return }
        if !closing {
            if final.status == .failed { failedQueue = true }
            if paused { hold(order.map(\.draft), afterFailure: final.status == .failed) }
            if final.status != .interrupted { finished(draft, final) }
            advance()
        }
    }

    func stopBeforeDelete(_ draft: AgentDraft) async throws {
        let wasActive = activeDraft === draft
        if wasActive, let active = task {
            active.cancel()
            await active.value
        }
        guard !isolationFailed else { throw AgentError.isolation("process_group") }
        if priority?.draft === draft { priority = nil }
        if wasActive { paused = false }
    }

    func finishDeletion(_ draft: AgentDraft) {
        if draft.deleted {
            order.removeAll { $0.draft === draft }
        } else {
            hold([draft], afterFailure: true)
        }
        advance()
    }

    func continueAfterCancelledQuit() {
        closing = false
        stoppingForShutdown = false
    }

    func shutdown() async {
        closing = true
        let active = task
        stoppingForShutdown = active?.isCancelled == false
        active?.cancel()
        await active?.value
    }
}
