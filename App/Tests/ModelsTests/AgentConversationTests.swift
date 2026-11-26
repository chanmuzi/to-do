import Foundation
import Testing
@testable import Models

@Suite struct AgentConversationTests {
    @Test func requestAndProposalsRoundTrip() throws {
        let note = NoteID.make()
        var value = AgentConversation(origin: note, context: [.note(note)])
        let requestID = UUID(), runID = UUID()
        let proposals = AgentProposal.Status.allCases.map { state in
            AgentProposal(id: UUID(), requestID: requestID, runID: runID, toolCallID: "call",
                          target: .note(note), title: "할 일", content: .todos(["확인"]),
                          createdAt: Date(), status: state)
        }
        value.requests = [AgentRequest(id: requestID, runID: runID, engine: "claude", status: .completed,
                                       userText: "\n  \n정리해 주세요\n다음 줄", steps: [], proposals: proposals)]
        #expect(value.name == "정리해 주세요")
        #expect(try JSONDecoder().decode(AgentConversation.self, from: JSONEncoder().encode(value)) == value)
    }
}

extension AgentConversationTests {
    @Test func migratesLegacyTargetsAndKeepsAnEmptyContextIndependent() throws {
        let id = UUID()
        let data = Data(#"{"id":"\#(id)","createdAt":0,"targets":["origin","second"]}"#.utf8)
        var value = try JSONDecoder().decode(AgentConversation.self, from: data)
        let origin = NoteID(rawValue: "origin"), second = NoteID(rawValue: "second")
        #expect(value.origin == origin && value.context == [.note(origin), .note(second)])
        for items: [AgentContextItem] in [[], [.space(.make()), .view(.today), .view(.pinned),
                                                .period(.today), .period(.thisWeek), .period(.lastSevenDays),
                                                .period(.day(.init(Date())))]] {
            value.context = items
            let saved = try JSONEncoder().encode(value)
            let json = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            #expect(json["targets"] == nil && json["formatVersion"] as? Int == 2)
            let read = try JSONDecoder().decode(AgentConversation.self, from: saved)
            #expect(read == value && read.origin == origin)
        }
    }
}
