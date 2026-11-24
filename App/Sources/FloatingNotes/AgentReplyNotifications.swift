import Agent
import AgentRunner
import Foundation
import Models

struct AgentReplyNotifications {
    var showsConversation: (UUID) -> Bool
    var deliver: (AgentReplyNotification) async throws -> Bool = { try await $0.deliver() }
    var log: @MainActor (String) -> Void = AppLog.warning

    @discardableResult
    func finished(_ draft: AgentDraft, _ request: AgentRequest) -> Task<Void, Never>? {
        let conversation = draft.conversation
        guard !showsConversation(conversation.id) else { return nil }
        let body: String
        switch request.status {
        case .completed:
            let lines = NotePreviewText.firstLines(in: request.answer ?? "", limit: 2)
            body = lines.isEmpty ? "끝났어요" : lines.joined(separator: "\n")
        case .failed:
            let reason = request.failure ?? "막혔어요"
            body = reason + (request.resumeTime.map { "\n" + $0 + "부터 다시 돼요" } ?? "")
        default:
            return nil
        }
        let notice = AgentReplyNotification(conversation: conversation.id, request: request.id,
                                            proposal: request.status == .completed ? request.proposals.first?.id : nil,
                                            title: NotePreviewText.firstLine(in: request.userText) ?? conversation.name,
                                            body: body)
        return Task {
            do {
                if try await !deliver(notice) { log("알림 권한이 없어 요청 결과를 알리지 못했습니다.") }
            } catch { log("요청 결과를 알리지 못했습니다. " + error.localizedDescription) }
        }
    }
}
