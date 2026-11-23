import Foundation
import Testing
@testable import Models

@Suite struct AgentConversationTests {
    @Test func requestAndProposalsRoundTrip() throws {
        var value = AgentConversation(targets: [.make()])
        let requestID = UUID(), runID = UUID()
        let proposals = AgentProposal.Status.allCases.map { state in
            AgentProposal(id: UUID(), requestID: requestID, runID: runID, toolCallID: "call",
                          target: .note(value.targets[0]), title: "할 일", content: .todos(["확인"]),
                          createdAt: Date(), status: state)
        }
        value.requests = [AgentRequest(id: requestID, runID: runID, engine: "claude", status: .completed,
                                       userText: "\n  \n정리해 주세요\n다음 줄", steps: [], proposals: proposals)]
        #expect(value.name == "정리해 주세요")
        #expect(try JSONDecoder().decode(AgentConversation.self, from: JSONEncoder().encode(value)) == value)
    }
}
