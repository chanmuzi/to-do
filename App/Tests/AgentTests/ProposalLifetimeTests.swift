import Agent
import Foundation
import Models
import Store
import Testing

@Suite struct ProposalLifetimeTests {
    @Test(arguments: ["", "[ ] 같은 줄\r\n\r\n", "\u{feff}---\r\ntitle: 메모\r\n---\r\n    ```\r\n내용\r\n", "---\ntitle: 메모\n---"])
    func acceptRecoverUndo(original: String) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let notes = try FileNoteStore(location: location)
        let store = AgentStore(location: location)
        let file = root.appending(path: "fixture.md")
        let bytes = Data(original.utf8)
        try bytes.write(to: file)
        var conversation = AgentConversation(targets: [])
        var request = AgentRequest(id: UUID(), text: "요청", engine: "claude", model: nil)
        let input = TodoSubmission(noteID: "fixture", lines: ["같은 줄", "다음 줄"], version: TodoSubmission.fingerprint(bytes))
        let p = AgentProposal.submitted(input, key: "접수", request: request, source: nil)
        request.proposals = [p]
        conversation.requests = [request]
        let draft = AgentDraft(conversation, store: store)
        try #require(try draft.acceptProposal(p.id, notes: notes))
        #expect(try !draft.acceptProposal(p.id, notes: notes))
        let applied = try Data(contentsOf: file)
        #expect(applied != bytes)
        // 노트 저장 직후 종료되어 대화에는 아직 미완료 영수증이 남았다.
        draft.change {
            $0.requests[0].proposals[0].operation = .accept
            $0.requests[0].proposals[0].status = .pending
        }
        let restarted = AgentDraft(try #require(store.loadConversations { _ in }.first), store: store)
        try restarted.recoverProposals(notes: notes)
        #expect(restarted.proposal(p.id)?.status == .accepted)
        #expect(try Data(contentsOf: file) == applied)
        try restarted.undoProposal(p.id, notes: notes)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(restarted.proposal(p.id)?.status == .undone)

        try Data("고친 글".utf8).write(to: file)
        let stale = AgentDraft(conversation, store: store)
        #expect(throws: StoreError.self) { try stale.acceptProposal(p.id, notes: notes) }
        #expect(stale.proposal(p.id)?.requiresReview == true)
        try stale.reviewProposal(p.id, notes: notes)
        try stale.discardProposal(p.id)
        #expect(try !stale.acceptProposal(p.id, notes: notes))
        #expect(try Data(contentsOf: file) == Data("고친 글".utf8))
    }
}
