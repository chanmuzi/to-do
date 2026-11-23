import Foundation
import Models
import Observation
import Store

@Observable package final class AgentDraft {
    package var conversation: AgentConversation
    package var writeError: Error?
    var errorMessage: String? { writeError.map { "대화를 저장하지 못했습니다. " + $0.localizedDescription } }
    package private(set) var deleted = false
    package var deleting = false

    @discardableResult package func rename(_ input: String) -> Bool {
        guard !conversation.requests.isEmpty else { return false }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != conversation.name else { return true }
        return change { $0.customName = name }
    }

    package func deleteFile() throws {
        try store.deleteConversation(conversation.id)
        deleted = true
        writeError = nil
    }

    var showsHistory = false
    var expanded: Set<UUID> = []
    var hovered: UUID?
    #if DEBUG
    var still = false
    #endif
    private let store: AgentStore

    package init(_ conversation: AgentConversation, store: AgentStore) {
        self.conversation = conversation
        self.store = store
    }

    package func update(_ text: String) {
        guard !deleted, conversation.draft != text else { return }
        conversation.draft = text
        conversation.updatedAt = Date()
        save()
    }

    package func markSeen(at now: Date = Date()) {
        guard !deleted, !conversation.requests.isEmpty, conversation.seenAt.map({ $0 < conversation.updatedAt }) ?? true else { return }
        var next = conversation
        next.seenAt = now
        do {
            try store.save(next)
            conversation = next
            writeError = nil
        } catch { writeError = error }
    }

    package func save() {
        guard !deleted else { return }
        do { try store.save(conversation); writeError = nil }
        catch { writeError = error }
    }

    /// 줄에서 꺼내기와 전송 예약은 디스크에 반영된 뒤에만 화면에도 반영한다.
    @discardableResult package func change(_ edit: (inout AgentConversation) -> Void) -> Bool {
        guard !deleted, !deleting else { return false }
        var next = conversation
        edit(&next)
        next.updatedAt = Date()
        do {
            try store.save(next)
            conversation = next
            writeError = nil
            return true
        } catch { writeError = error; return false }
    }

    package func remove(_ id: UUID, editing: Bool) {
        guard let item = conversation.queued.first(where: { $0.id == id }),
              !editing || conversation.draft.isEmpty else { return }
        change {
            $0.queued.removeAll { $0.id == id }
            if editing { $0.draft = item.text }
        }
    }
}
