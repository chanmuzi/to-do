import Foundation
import Models
import Testing
@testable import Store

/// 휴지통을 거치지 않고 지우기(D-040, 아무것도 적지 않은 노트를 치울 때만 쓴다).
@Suite @MainActor struct StoreDeleteTests {
    let temporary = TemporaryStore()

    @Test func deleteRemovesTheFileWithoutTrashAndAnnouncesIt() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .seconds(60))
        let note = try store.create(NoteDraft())
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }
        _ = try store.scheduleUpdate(note.id) { $0.title = "" }

        try store.delete(note.id)

        #expect(!FileManager.default.fileExists(atPath: temporary.noteFile(note.id.rawValue).path))
        #expect(try store.listTrash().notes.isEmpty)
        #expect(!store.hasPendingChanges(note.id))
        #expect(changes.last == StoreChange(id: note.id, kind: .removed, origin: .local))
        #expect(throws: StoreError.noteNotFound(note.id)) { try store.load(note.id) }
        // 폴더를 다시 훑어도 다른 프로그램이 지운 것으로 다시 알리지 않는다.
        let before = changes.count
        try store.refresh()
        #expect(changes.count == before)
        withExtendedLifetime(observation) {}
    }

    @Test func deletingAMissingNoteThrows() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location)
        let missing = NoteID(rawValue: "없는 노트")
        #expect(throws: StoreError.noteNotFound(missing)) { try store.delete(missing) }
    }

    @Test func blankMeansNoTitleNoBodyAndNoReminder() {
        func note(_ title: String, _ body: String, reminder: Date? = nil, color: String? = nil) -> Note {
            Note(
                id: NoteID(rawValue: "n"), title: title, body: body, colorID: color.map(PaletteID.init(rawValue:)),
                reminder: reminder, created: .distantPast, modified: .distantPast
            )
        }
        #expect(note("", "").isBlank)
        #expect(note(" ", " \n\t\n").isBlank)
        #expect(note("", "", color: "tint-1").isBlank)
        #expect(!note("제목", "").isBlank)
        #expect(!note("", "글").isBlank)
        #expect(!note("", "[ ]").isBlank)
        #expect(!note("", "", reminder: .distantFuture).isBlank)
    }
}
