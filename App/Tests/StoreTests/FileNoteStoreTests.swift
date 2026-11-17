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

    @Test(arguments: ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"])
    func allTitleWritesStaySingleLine(separator: String) throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let created = try store.create(NoteDraft(title: "첫" + separator + "제목", body: sampleBody))
        #expect(created.title == "첫 제목")
        #expect(try makeStore().load(created.id).title == "첫 제목")
        let updated = try store.update(created.id) { $0.title = "다음" + separator + "제목" }
        #expect(updated.title == "다음 제목")
        #expect(try makeStore().load(created.id).title == "다음 제목")
        let pending = try store.scheduleUpdate(created.id) { $0.title = "자동" + separator + "저장" }
        #expect(pending.title == "자동 저장")
        #expect(try store.load(created.id).title == "자동 저장")
        try store.flushPendingSaves()
        let reloaded = try makeStore().load(created.id)
        #expect(reloaded.title == "자동 저장")
        #expect(Array(reloaded.body.utf8) == Array(sampleBody.utf8))
    }

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

        let saved = try store.update(created.id) { note in
            note.title = "바꾼 제목"
            note.body = sampleBody + "\n추가\n"
            note.colorID = PaletteID(rawValue: "tint-1")
            note.reminder = Date(timeIntervalSince1970: 1_800_000_000)
        }

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

        #expect(try store.list().notes.map(\.id) == [second.id, first.id])
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
        try store.update(NoteID(rawValue: "tagged")) { $0.body = "고친 본문" }
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
        #expect(try store.update(note.id) { _ in }.modified == old)
        #expect(try store.update(note.id) { $0.body = "본문" }.modified == old)
    }

    @Test func trashMovesTheFileAndRestoreBringsItBack() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "버릴 노트", body: sampleBody))
        let keep = try store.create(NoteDraft(title: "남길 노트"))

        try store.moveToTrash(note.id)
        #expect(try store.list().notes.map(\.id) == [keep.id])
        #expect(throws: StoreError.noteNotFound(note.id)) { try store.load(note.id) }
        #expect(!FileManager.default.fileExists(atPath: temporary.noteFile(note.id.rawValue).path))
        let trashed = temporary.location.trashDirectory.appendingPathComponent("\(note.id.rawValue).md")
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(try store.listTrash().notes.map(\.id) == [note.id])
        #expect(try store.listTrash().notes.first?.body == sampleBody)

        #expect(throws: StoreError.noteNotFound(note.id)) { try store.moveToTrash(note.id) }

        let restored = try store.restoreFromTrash(note.id)
        #expect(restored.body == sampleBody)
        #expect(restored.title == "버릴 노트")
        #expect(try store.listTrash().notes.isEmpty)
        #expect(Set(try store.list().notes.map(\.id)) == [note.id, keep.id])
    }

    @Test func missingNoteThrows() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        #expect(throws: StoreError.noteNotFound(NoteID(rawValue: "none"))) {
            try store.load(NoteID(rawValue: "none"))
        }
    }

    /// 읽지 못하는 `.md` 하나가 목록 전체를 막지 않는다. 읽은 노트와 실패를 함께 돌려준다.
    @Test func unreadableFilesAreReportedAlongsideReadableNotes() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let good = try store.create(NoteDraft(title: "멀쩡한 노트"))
        try Data([0xFF, 0xFE, 0xFD]).write(to: temporary.noteFile("broken"))
        try FileManager.default.createDirectory(at: temporary.noteFile("x"), withIntermediateDirectories: true)

        let listing = try store.list()
        #expect(listing.notes.map(\.id) == [good.id])
        #expect(listing.failures == [
            NoteReadFailure(
                id: NoteID(rawValue: "broken"), url: temporary.noteFile("broken"),
                error: .unreadableFile(temporary.noteFile("broken"))
            ),
            NoteReadFailure(
                id: NoteID(rawValue: "x"), url: temporary.noteFile("x"),
                error: .unreadableFile(temporary.noteFile("x"))
            ),
        ])
        #expect(throws: StoreError.unreadableFile(temporary.noteFile("broken"))) {
            try store.load(NoteID(rawValue: "broken"))
        }
        // 새 저장소도 이 폴더로 만들어진다(앱이 켜진다).
        #expect(try makeStore().list().notes.count == 1)
    }

    /// 읽지 못한 날짜와 초 아래 자리가 있는 날짜가 본문을 고쳐 저장한 뒤에도 남는다.
    @Test func unparsableAndFractionalDatesSurviveABodyEdit() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let id = NoteID(rawValue: "dates")
        try Data("---\ntitle: 날짜\nreminder: 2026-11-17 09:00\ncreated: 2026-11-16T12:08:00.123Z\n---\n본문"
            .utf8).write(to: temporary.noteFile("dates"))

        let loaded = try store.load(id)
        #expect(loaded.reminder == nil)
        #expect(abs(loaded.created.timeIntervalSince1970 - 1_794_830_880.123) < 0.0005)
        try store.update(id) { $0.body = "고친 본문" }
        #expect(try String(contentsOf: temporary.noteFile("dates"), encoding: .utf8)
            == "---\ntitle: 날짜\nreminder: 2026-11-17 09:00\ncreated: 2026-11-16T12:08:00.123Z\n---\n고친 본문")

        // 리마인더를 새로 정하면 그 줄만 바뀐다.
        try store.update(id) { $0.reminder = Date(timeIntervalSince1970: 1_800_000_000) }
        #expect(try String(contentsOf: temporary.noteFile("dates"), encoding: .utf8)
            == "---\ntitle: 날짜\nreminder: 2027-01-15T08:00:00Z\ncreated: 2026-11-16T12:08:00.123Z\n---\n고친 본문")
    }

    /// BOM으로 시작하는 파일도 머리를 읽고, 저장해도 머리가 하나 더 생기지 않는다.
    @Test func fileStartingWithByteOrderMarkKeepsASingleHeader() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let id = NoteID(rawValue: "bom")
        try Data([0xEF, 0xBB, 0xBF] + Array("---\ntitle: 윈도에서\n---\n본문".utf8)).write(to: temporary.noteFile("bom"))

        #expect(try store.load(id).title == "윈도에서")
        try store.update(id) { $0.body = "고친 본문" }
        // BOM은 그대로고 머리는 하나다(머리에 없던 만든 날짜만 더해진다).
        let data = try Data(contentsOf: temporary.noteFile("bom"))
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text.hasPrefix("---\ntitle: 윈도에서\ncreated: "))
        #expect(text.hasSuffix("Z\n---\n고친 본문"))
        #expect(text.components(separatedBy: "---\n").count == 3)
        #expect(try makeStore().load(id).title == "윈도에서")
    }
}
