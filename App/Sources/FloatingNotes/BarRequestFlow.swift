import Agent
import Capture
import Foundation
import Models

final class BarRequestFlow {
    private let agent: AgentWindowCoordinator
    private unowned let requests: AgentRequestCoordinator

    init(agent: AgentWindowCoordinator, requests: AgentRequestCoordinator) {
        self.agent = agent
        self.requests = requests
    }

    func submit(_ text: String) -> AgentDraft? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let draft = agent.newRecord()
        guard requests.submit(draft, text: text, fromInput: false, fromBar: true) else {
            if let error = draft.writeError { AppLog.warning(error.localizedDescription) }
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
}
