import Agent
import AgentRunner
import Capture
import Foundation
import Models

final class BarRequestFlow {
    private let agent: AgentWindowCoordinator
    private unowned let requests: AgentRequestCoordinator
    var showsConversation: (UUID) -> Bool
    var deliver: (AgentReplyNotification) async throws -> Bool = { try await $0.deliver() }
    var log: @MainActor (String) -> Void = AppLog.warning

    init(agent: AgentWindowCoordinator, requests: AgentRequestCoordinator) {
        self.agent = agent
        self.requests = requests
        showsConversation = agent.showsConversation
    }

    func submit(_ text: String) -> AgentDraft? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let draft = agent.newRecord()
        guard requests.submit(draft, text: text, fromInput: false, fromBar: true) else {
            if let error = draft.writeError { log(error.localizedDescription) }
            return nil
        }
        agent.rememberBar(draft)
        return draft
    }

    var recent: CaptureRecentRequest? {
        guard let draft = agent.recentBar, !draft.deleted, let id = draft.conversation.barRequestID else { return nil }
        let chat = draft.conversation
        if let queued = chat.queued.first(where: { $0.id == id }) {
            return .init(id: chat.id, question: NotePreviewText.firstLine(in: queued.text) ?? queued.text,
                         detail: "차례를 기다리는 중", date: chat.createdAt, face: .think)
        }
        guard let request = chat.requests.first(where: { $0.id == id }) else { return nil }
        let detail: String
        switch request.status {
        case .running: detail = request.progressTitle
        case .failed: detail = request.failure ?? "막혔어요"
        case .interrupted: detail = "여기서 멈췄어요"
        default: detail = request.answer.flatMap(NotePreviewText.firstLine) ?? "끝났어요"
        }
        return .init(id: chat.id, question: NotePreviewText.firstLine(in: request.userText) ?? request.userText,
                     detail: detail, date: request.steps.last?.endedAt ?? chat.createdAt, face: request.face)
    }

    @discardableResult func finished(_ draft: AgentDraft, _ request: AgentRequest) -> Task<Void, Never>? {
        guard !showsConversation(draft.conversation.id) else { return nil }
        let body = request.status == .failed ? request.failure ?? "막혔어요"
            : NotePreviewText.firstLines(in: request.answer ?? "", limit: 2).joined(separator: "\n")
        let notice = AgentReplyNotification(conversation: draft.conversation.id, request: request.id,
                                            title: NotePreviewText.firstLine(in: request.userText) ?? draft.conversation.name, body: body)
        return Task {
            do {
                if try await !deliver(notice) { log("알림 권한이 없어 막대 요청의 결과 알림을 건너뜁니다.") }
            } catch { log("막대 요청의 결과를 알리지 못했습니다. " + error.localizedDescription) }
        }
    }
}
