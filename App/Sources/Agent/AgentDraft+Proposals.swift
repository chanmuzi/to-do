import Foundation
import Models
import Store

extension AgentDraft {
    package func proposal(_ id: UUID) -> AgentProposal? {
        conversation.requests.lazy.flatMap(\.proposals).first { $0.id == id }
    }

    private func updateProposal(_ id: UUID, recordsActivity: Bool = true, _ edit: (inout AgentProposal) -> Void) throws {
        guard let r = conversation.requests.firstIndex(where: { $0.proposals.contains { $0.id == id } }),
              let p = conversation.requests[r].proposals.firstIndex(where: { $0.id == id }),
              change(recordsActivity: recordsActivity, { edit(&$0.requests[r].proposals[p]) }) else { throw writeError ?? CocoaError(.fileWriteUnknown) }
    }

    package func markProposalSeen(_ id: UUID) throws {
        if proposal(id)?.seenAt == nil { try updateProposal(id, recordsActivity: false) { $0.seenAt = Date() } }
    }

    package func discardProposal(_ id: UUID) throws {
        guard let value = proposal(id), value.status == .pending, value.operation == nil else { return }
        try updateProposal(id) { $0.status = .discarded; $0.seenAt = Date() }
    }

    /// 새 미리보기를 실제로 열었을 때만 그 기반을 교체한다.
    package func reviewProposal(_ id: UUID, notes: FileNoteStore) throws {
        guard let p = proposal(id), p.status == .pending, let target = p.targetID, p.operation == nil else { return }
        let version = try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8))
        try updateProposal(id, recordsActivity: false) { $0.baseVersion = version; $0.requiresReview = nil; $0.seenAt = Date() }
    }

    @discardableResult package func acceptProposal(_ id: UUID, notes: FileNoteStore) throws -> Bool {
        guard let p = proposal(id), p.status == .pending, p.operation == nil, let target = p.targetID else { return false }
        let text = try notes.proposalText(target)
        let receipt = try notes.prepareTodos(p.lines, text: text)
        guard p.requiresReview != true, receipt.previousFingerprint == p.baseVersion else {
            try updateProposal(id) { $0.requiresReview = true }
            throw StoreError.conflict(target)
        }
        try updateProposal(id) { $0.receipt = receipt; $0.operation = .accept }
        do { try notes.applyTodos(receipt, to: target, undo: false) }
        catch {
            try recoverProposals(notes: notes)
            throw error
        }
        try updateProposal(id) { $0.status = .accepted; $0.operation = nil; $0.seenAt = Date() }
        return true
    }

    package func undoProposal(_ id: UUID, notes: FileNoteStore) throws {
        guard let p = proposal(id), p.status == .accepted, p.operation == nil,
              let target = p.targetID, let receipt = p.receipt else { return }
        guard try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8)) == receipt.appliedFingerprint
        else { throw StoreError.conflict(target) }
        try updateProposal(id) { $0.operation = .undo }
        do { try notes.applyTodos(receipt, to: target, undo: true) }
        catch {
            try recoverProposals(notes: notes)
            throw error
        }
        try updateProposal(id) { $0.status = .undone; $0.operation = nil }
    }

    package func recoverProposals(notes: FileNoteStore) throws {
        for p in conversation.requests.flatMap(\.proposals) {
            guard let operation = p.operation, let target = p.targetID, let receipt = p.receipt else { continue }
            let current = try? TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8))
            try updateProposal(p.id) {
                if current == receipt.appliedFingerprint { $0.status = .accepted }
                else if current == receipt.previousFingerprint { $0.status = operation == .undo ? .undone : .pending }
                else { $0.requiresReview = true }
                $0.operation = nil
            }
        }
    }
}
