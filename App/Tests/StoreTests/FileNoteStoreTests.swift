import Foundation
import Testing
import Models
@testable import Store

@Suite @MainActor struct FileNoteStoreTests {
    let temporary = TemporaryStore()

    private func makeStore(autosaveDelay: Duration = .milliseconds(50)) throws -> FileNoteStore {
        try FileNoteStore(location: temporary.location, autosaveDelay: autosaveDelay)
    }

    private let sampleBody = "첫 줄\n- [ ] 투두\n\t- 하위  \n==형광펜=={2}\n\n```\ncode\n```\n끝에 줄바꿈 없음"

    @Test func createWritesOneMarkdownFileWithFrontmatter() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let reminder = Date(timeIntervalSince1970: 1_800_000_000)
        let note = try store.create(NoteDraft(
            title: "회의", body: sampleBody, spaceID: SpaceID(rawValue: "work"),
            colorID: PaletteID(rawValue: "tint-3"), reminder: reminder
        ))

        let text = try String(contentsOf: temporary.noteFile(note.id.rawValue), encoding: .utf8)
        #expect(text.hasPrefix("---\ntitle: \"회의\"\nspace: \"work\"\ncolor: tint-3\nreminder: 2027-01-15T08:00:00Z\ncreated: "))
        #expect(text.hasSuffix("\n---\n" + sampleBody))
        // 창 상태는 노트 파일에 없다.
        #expect(!text.contains("pinned"))
        #expect(!text.contains("frame"))
    }

    @Test func loadReturnsExactlyWhatWasSaved() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let created = try store.create(NoteDraft(title: "제목", body: sampleBody))
        let loaded = try store.load(created.id)
        #expect(loaded == created)
        #expect(Array(loaded.body.utf8) == Array(sampleBody.utf8))

        var edited = loaded
        edited.title = "바꾼 제목"
        edited.body = sampleBody + "\n추가\n"
        edited.colorID = PaletteID(rawValue: "tint-1")
        edited.reminder = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = try store.save(edited)

        // 새 저장소 인스턴스로 다시 읽어도 같다.
        let reloaded = try makeStore().load(created.id)
        #expect(reloaded == saved)
        #expect(reloaded.created == created.created)
        #expect(reloaded.body == sampleBody + "\n추가\n")
    }

    @Test func listSortsByModifiedAndIgnoresOtherFiles() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let first = try store.create(NoteDraft(title: "첫째"))
        let second = try store.create(NoteDraft(title: "둘째"))
        let old = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes(
            [.modificationDate: old], ofItemAtPath: temporary.noteFile(first.id.rawValue).path
        )
        try Data("x".utf8).write(to: temporary.location.notesDirectory.appendingPathComponent("메모.txt"))

        #expect(try store.list().map(\.id) == [second.id, first.id])
    }

    @Test func externallyWrittenMarkdownIsReadable() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        try Data("# 밖에서 만든 파일\n".utf8).write(to: temporary.noteFile("handmade"))
        let note = try store.load(NoteID(rawValue: "handmade"))
        #expect(note.title == "")
        #expect(note.body == "# 밖에서 만든 파일\n")
    }

    @Test func saveKeepsUnknownFrontmatterLines() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        try Data("---\ntitle: 손으로\ntags: [a]\n---\n본문".utf8).write(to: temporary.noteFile("tagged"))
        var note = try store.load(NoteID(rawValue: "tagged"))
        note.body = "고친 본문"
        try store.save(note)
        let text = try String(contentsOf: temporary.noteFile("tagged"), encoding: .utf8)
        #expect(text.contains("\ntags: [a]\n"))
        #expect(text.hasSuffix("---\n고친 본문"))
    }

    @Test func savingUnchangedNoteDoesNotRewriteTheFile() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "그대로", body: "본문"))
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: old], ofItemAtPath: temporary.noteFile(note.id.rawValue).path
        )
        #expect(try store.save(note).modified == old)
    }

    @Test func trashMovesTheFileAndRestoreBringsItBack() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "버릴 노트", body: sampleBody))
        let keep = try store.create(NoteDraft(title: "남길 노트"))

        try store.moveToTrash(note.id)
        #expect(try store.list().map(\.id) == [keep.id])
        #expect(throws: StoreError.noteNotFound(note.id)) { try store.load(note.id) }
        #expect(!FileManager.default.fileExists(atPath: temporary.noteFile(note.id.rawValue).path))
        let trashed = temporary.location.trashDirectory.appendingPathComponent("\(note.id.rawValue).md")
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(try store.listTrash().map(\.id) == [note.id])
        #expect(try store.listTrash().first?.body == sampleBody)

        #expect(throws: StoreError.noteNotFound(note.id)) { try store.moveToTrash(note.id) }

        let restored = try store.restoreFromTrash(note.id)
        #expect(restored.body == sampleBody)
        #expect(restored.title == "버릴 노트")
        #expect(try store.listTrash().isEmpty)
        #expect(Set(try store.list().map(\.id)) == [note.id, keep.id])
    }

    @Test func missingNoteThrows() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        #expect(throws: StoreError.noteNotFound(NoteID(rawValue: "none"))) {
            try store.load(NoteID(rawValue: "none"))
        }
    }

    @Test func nonUTF8FileIsReportedNotSkipped() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        try Data([0xFF, 0xFE, 0xFD]).write(to: temporary.noteFile("broken"))
        #expect(throws: StoreError.unreadableFile(temporary.noteFile("broken"))) { try store.list() }
    }
}
