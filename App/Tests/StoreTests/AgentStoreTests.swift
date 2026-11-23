import Foundation
import Models
import Store
import Testing

@MainActor @Suite struct AgentStoreTests {
    @Test func missingLegacyDamagedAndFutureFilesStayIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let location = StoreLocation.isolated(notesDirectory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(location: location)
        var warnings: [String] = []
        #expect(try store.loadConversations { warnings.append($0) }.isEmpty)
        #expect(try store.readInstructions() == "")
        var draft = AgentConversation(targets: [NoteID(rawValue: "옛 노트")])
        draft.draft = "초안"
        try store.save(draft)
        let folder = location.stateDirectory.appending(path: "agent/conversations")
        let legacy = UUID()
        try Data(#"{"id":"\#(legacy)","createdAt":0}"#.utf8).write(to: folder.appending(path: legacy.uuidString + ".json"))
        let invalid = [Data("{".utf8), Data(#"{"formatVersion":2}"#.utf8)]
        let paths = invalid.map { _ in folder.appending(path: UUID().uuidString + ".json") }
        for (url, data) in zip(paths, invalid) { try data.write(to: url) }
        let read = try store.loadConversations { warnings.append($0) }
        #expect(read.count == 2 && read.contains(draft))
        #expect(read.first { $0.id == legacy }?.draft == "")
        #expect(warnings.count == 2)
        for (url, data) in zip(paths, invalid) { #expect(try Data(contentsOf: url) == data) }
        let instructions = "# 규칙\n\n  원문\n"
        try store.saveInstructions(instructions)
        #expect(try store.readInstructions() == instructions)
        #expect(try FileNoteStore(location: location).list().notes.isEmpty)
    }
}
