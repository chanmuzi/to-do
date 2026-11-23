import Agent
import Foundation
import Models
import Scheduling
import Store
import Testing

@MainActor @Suite struct ProposalScheduleTests {
    @Test(arguments: ["immediate", "denied", "saveFailure", "linked", "deleteConversation"])
    func approvalRecoveryAndIDScopedUndo(mode: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let notes = try FileNoteStore(location: location)
        let note = try notes.create(.init(title: "회의", body: "보존"))
        let bridge = FakeCalendarBridge()
        bridge.isAllowed = mode != "denied"
        if mode == "saveFailure" { bridge.failure = .readOnly }
        let service = ScheduleService(notes: notes, notifier: FakeReminderNotifier(), makeBridge: { bridge })
        try service.start()
        defer { service.stop() }
        let store = AgentStore(location: location)
        var request = AgentRequest(id: UUID(), text: "예정", engine: "fixture", model: nil)
        let source: [String: Any] = ["kind": "add_reminder", "title": "반납", "note_id": note.id.rawValue,
                                    "date_only": true, "start": "2028-02-29", "time_zone": "Pacific/Kiritimati"]
        let event = source.merging(["kind": "add_event", "date_only": false, "start": "2028-02-29T14:30:00",
                                    "end": "2028-02-29T15:30:00"]) { _, n in n }
        for args in [source, event] {
            let input = try JSONDecoder().decode(ProposalArguments.self, from: JSONSerialization.data(withJSONObject: args))
            let digest = try TodoSubmission.fingerprint(Data(notes.proposalText(note.id).utf8))
            request.proposals.append(try .submitted(.init(arguments: input, version: digest), key: input.kind.rawValue,
                                                     request: request, source: note.id, reservedID: .make()))
        }
        let draft = AgentDraft(.init(targets: [note.id]), store: store)
        draft.change { $0.requests = [request] }
        #expect(try notes.load(note.id).schedules.isEmpty)
        #expect(bridge.saves == 0 && bridge.authorizationRequests.isEmpty)
        for p in request.proposals {
            try draft.reviewProposal(p.id, notes: notes)
            try #require(try draft.acceptProposal(p.id, notes: notes))
            service.register(note.id, itemID: p.id.uuidString, requestPermission: false)
        }
        let first = request.proposals[0], second = request.proposals[1]
        if mode != "immediate" { await service.flush() }
        let local = try notes.load(note.id).schedules
        #expect(local.map(\.id) == [first.id.uuidString, second.id.uuidString])
        #expect(Calendar.current.component(.day, from: local[0].start) == 29)
        #expect(local[1].end?.timeIntervalSince(local[1].start) == 3600)
        if mode == "saveFailure" { #expect(local.allSatisfy { $0.syncError != nil && $0.link == nil }) }
        if mode == "denied" || mode == "immediate" { #expect(bridge.saves == 0) }
        draft.change { $0.requests[0].proposals[0].operation = .accept; $0.requests[0].proposals[0].status = .pending }
        let recovered = AgentDraft(try #require(store.loadConversations { _ in }.first), store: store)
        try recovered.recoverProposals(notes: notes)
        #expect(recovered.proposal(first.id)?.status == .accepted)
        #expect(try !recovered.acceptProposal(first.id, notes: notes))
        if mode == "deleteConversation" {
            try recovered.deleteFile()
            #expect(try store.loadConversations { _ in }.isEmpty)
            #expect(try notes.load(note.id).schedules.count == 2)
            #expect(bridge.items.count == 2)
            return
        }
        if mode == "linked" { bridge.failure = .readOnly }
        try recovered.undoProposal(first.id, notes: notes)
        await service.flush()
        if mode == "linked" {
            let pending = try #require(notes.load(note.id).schedules.first { $0.id == first.id.uuidString })
            #expect(pending.isDeleted && pending.link != nil && pending.syncError != nil)
            bridge.failure = nil
            service.refreshLinked()
            await service.flush()
        }
        #expect(try notes.load(note.id).schedules.map(\.id) == [second.id.uuidString])
        #expect(bridge.items[first.id.uuidString] == nil)
        #expect(try notes.load(note.id).body == "보존")
    }
}
