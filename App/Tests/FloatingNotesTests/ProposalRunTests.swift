import Agent
import AgentRunner
import Foundation
import Models
import Store
import Testing
@testable import FloatingNotes

@Suite struct ProposalRunTests {
    @Test(arguments: [false, true])
    func onlySuccessfulAttemptPublishes(_ shutdown: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let inbox = ProposalInbox(location: location)
        let draft = AgentDraft(.init(targets: []), store: AgentStore(location: location))
        var attempts: [UUID] = []
        let execute: AgentRequestCoordinator.Execute = { _, request, _ in
            let folder = try inbox.prepare(request.runID)
            let input = TodoSubmission(noteID: "a", lines: ["할 일"], version: "기반")
            try JSONEncoder().encode(input).write(to: folder.appending(path: "accepted.json"), options: .atomic)
            for (i, args) in [
                #"{"kind":"add_reminder","note_id":"a","title":"반납","date_only":true,"time_zone":"Asia/Seoul","start":"2028-02-29"}"#,
                #"{"kind":"add_event","note_id":"a","title":"회의","date_only":true,"time_zone":"Asia/Seoul","start":"2028-02-29","end":"2028-03-01"}"#,
                #"{"kind":"create_note","title":"새 노트","markdown":"[ ] 확인"}"#
            ].enumerated() {
                let arguments = try JSONDecoder().decode(ProposalArguments.self, from: Data(args.utf8))
                let entry = ProposalSubmission(arguments: arguments, version: arguments.note_id == nil ? nil : "기반")
                try JSONEncoder().encode(entry).write(to: folder.appending(path: "item-\(i).json"), options: .atomic)
            }
            attempts.append(request.runID)
            #expect(draft.conversation.requests[0].proposals.isEmpty)
            if attempts.count == 1 {
                if shutdown { try await Task.sleep(for: .seconds(5)) }
                throw AgentError.providerFailure
            }
            return "완료"
        }
        func coordinator() -> AgentRequestCoordinator {
            let queue = AgentRequestCoordinator(choice: { .init(provider: .claude, model: nil) }, note: { _ in nil }, execute: execute)
            queue.inbox = inbox
            return queue
        }
        let first = coordinator()
        first.submit(draft, text: "요청")
        for _ in 0..<100 where attempts.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        if shutdown { await first.shutdown() } else { await first.task?.value }
        let prior = try #require(draft.conversation.requests.first)
        #expect(prior.proposals.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: inbox.folder(prior.runID).path))
        let next = shutdown ? coordinator() : first
        if shutdown { next.restore([draft]) } else { next.retry(draft, id: prior.id) }
        while let task = next.task { await task.value }
        let request = try #require(draft.conversation.requests.first)
        #expect(attempts.count == 2 && attempts[0] != attempts[1])
        #expect(request.id == prior.id && request.proposals.count == 4)
        #expect(request.proposals.allSatisfy { $0.runID == attempts.last })
        #expect(!FileManager.default.fileExists(atPath: inbox.folder(request.runID).path))
    }
}
