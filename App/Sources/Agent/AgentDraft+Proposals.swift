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
        guard let p = proposal(id), p.status == .pending, p.operation == nil else { return }
        if case let .instructions(before, after) = p.content {
            let current = try store.instructionSnapshot()
            let rebased = try reviewedInstructions(before: before, after: after, current: current)
            try updateProposal(id, recordsActivity: false) {
                $0.content = .instructions(before: current, after: rebased)
                $0.baseVersion = TodoSubmission.fingerprint(Data(current.utf8))
                $0.requiresReview = nil
                $0.seenAt = Date()
            }
            return
        }
        guard let target = p.targetID else { return }
        let version = try TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8))
        try updateProposal(id, recordsActivity: false) { $0.baseVersion = version; $0.requiresReview = nil; $0.seenAt = Date() }
    }

    @discardableResult package func acceptProposal(_ id: UUID, notes: FileNoteStore) throws -> Bool {
        guard let p = proposal(id), p.status == .pending, p.operation == nil else { return false }
        let receipt: AgentProposal.Receipt
        let write: () throws -> Void
        if case let .instructions(before, after) = p.content, p.target == .instructions {
            let current = try store.instructionSnapshot()
            let version = TodoSubmission.fingerprint(Data(current.utf8))
            guard p.requiresReview != true, version == p.baseVersion, current.utf8.elementsEqual(before.utf8) else {
                try updateProposal(id) { $0.requiresReview = true }
                throw AgentStore.InstructionConflict.changed
            }
            receipt = .init(previousFingerprint: version, appliedFingerprint: TodoSubmission.fingerprint(Data(after.utf8)))
            write = { try self.store.saveInstructions(after) }
        } else if case .newNote(let target, let space) = p.target, case .newNote(let title, let body) = p.content {
            guard !notes.proposalFileExists(target), !notes.proposalFileExists(target, trash: true) else {
                throw StoreError.noteAlreadyExists(target)
            }
            let draft = NoteDraft(title: title, body: body, spaceID: space)
            let expected = notes.newNoteText(draft, created: p.createdAt)
            receipt = .init(previousFingerprint: "", appliedFingerprint: TodoSubmission.fingerprint(Data(expected.utf8)))
            write = { try notes.create(draft, id: target, created: p.createdAt) }
        } else if let target = p.targetID {
            let text = try notes.proposalText(target)
            let version = TodoSubmission.fingerprint(Data(text.utf8))
            guard p.requiresReview != true, version == p.baseVersion else {
                try updateProposal(id) { $0.requiresReview = true }
                throw StoreError.conflict(target)
            }
            if let item = p.scheduleItem {
                guard try !notes.proposalNote(target).schedules.contains(where: { $0.id == item.id }) else { throw StoreError.conflict(target) }
                receipt = .init(previousFingerprint: version, appliedFingerprint: "")
                write = { try notes.writeSchedule(item, in: target) }
            } else {
                receipt = try notes.prepareTodos(p.lines, text: text)
                write = { try notes.applyTodos(receipt, to: target, undo: false) }
            }
        } else { return false }
        try updateProposal(id) { $0.receipt = receipt; $0.operation = .accept }
        do { try write() }
        catch {
            try recoverProposals(notes: notes)
            throw error
        }
        try updateProposal(id) { $0.status = .accepted; $0.operation = nil; $0.seenAt = Date() }
        return true
    }

    package func undoProposal(_ id: UUID, notes: FileNoteStore, sharedScheduleTarget: Bool = false) throws {
        guard let p = proposal(id), p.status == .accepted, p.operation == nil,
              var receipt = p.receipt else { return }
        if case let .instructions(before, _) = p.content {
            let current = try store.instructionSnapshot()
            guard TodoSubmission.fingerprint(Data(current.utf8)) == receipt.appliedFingerprint else { throw AgentStore.InstructionConflict.changed }
            try updateProposal(id) { $0.operation = .undo }
            do { try store.saveInstructions(before) }
            catch { try recoverProposals(notes: notes); throw error }
            try updateProposal(id) { $0.status = .undone; $0.operation = nil }
            return
        }
        guard let target = p.createdNoteID ?? p.targetID else { return }
        if p.scheduleItem == nil {
            let text = try notes.proposalText(target)
            if TodoSubmission.fingerprint(Data(text.utf8)) != receipt.appliedFingerprint {
                guard sharedScheduleTarget, case .todos = p.content else { throw StoreError.conflict(target) }
                receipt = try notes.rebaseTodoUndo(receipt, text: text, id: target)
            }
        }
        try updateProposal(id) { $0.receipt = receipt; $0.operation = .undo }
        do {
            if p.createdNoteID != nil { try notes.moveToTrash(target) }
            else if let item = p.scheduleItem { try notes.removeSchedule(item.id, in: target) }
            else { try notes.applyTodos(receipt, to: target, undo: true) }
        }
        catch {
            try recoverProposals(notes: notes)
            throw error
        }
        try updateProposal(id) { $0.status = .undone; $0.operation = nil }
    }

    package func recoverProposals(notes: FileNoteStore) throws {
        for p in conversation.requests.flatMap(\.proposals) {
            guard let operation = p.operation, let receipt = p.receipt else { continue }
            if p.target == .instructions {
                let current = try TodoSubmission.fingerprint(Data(store.readInstructions().utf8))
                try updateProposal(p.id) {
                    if current == receipt.appliedFingerprint { $0.status = .accepted }
                    else if current == receipt.previousFingerprint { $0.status = operation == .undo ? .undone : .pending }
                    else { $0.requiresReview = true }
                    $0.operation = nil
                }
                continue
            }
            guard let target = p.createdNoteID ?? p.targetID else { continue }
            let current = try? TodoSubmission.fingerprint(Data(notes.proposalText(target).utf8))
            let item = p.scheduleItem.flatMap { item in
                try? notes.proposalNote(target).schedules.first { $0.id == item.id }
            }
            try updateProposal(p.id) {
                if p.scheduleItem != nil {
                    if let item, !item.isDeleted { $0.status = .accepted }
                    else if operation == .undo && current != nil { $0.status = .undone }
                    else if current == receipt.previousFingerprint { $0.status = .pending }
                    else { $0.requiresReview = true }
                } else if p.createdNoteID != nil && !notes.proposalFileExists(target) {
                    if operation == .undo && notes.proposalFileExists(target, trash: true) { $0.status = .undone }
                    else if operation == .accept && !notes.proposalFileExists(target, trash: true) { $0.status = .pending }
                    else { $0.requiresReview = true }
                } else if current == receipt.appliedFingerprint { $0.status = .accepted }
                else if current == receipt.previousFingerprint { $0.status = operation == .undo ? .undone : .pending }
                else { $0.requiresReview = true }
                $0.operation = nil
            }
        }
    }
}
