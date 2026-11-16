import Foundation
import Testing
import Models
@testable import Store

/// 같은 노트를 여러 곳에서 고치는 경우와 다른 프로그램이 파일을 고치는 경우.
@Suite @MainActor struct StoreConcurrentEditTests {
    let temporary = TemporaryStore()

    private func makeStore(autosaveDelay: Duration = .seconds(60)) throws -> FileNoteStore {
        try FileNoteStore(location: temporary.location, autosaveDelay: autosaveDelay)
    }

    private func diskText(_ id: NoteID) throws -> String {
        try String(contentsOf: temporary.noteFile(id.rawValue), encoding: .utf8)
    }

    /// 다른 프로그램처럼 파일 끝에 덧붙인다(제자리 수정).
    private func appendOutside(_ text: String, to id: NoteID) throws {
        let handle = try FileHandle(forWritingTo: temporary.noteFile(id.rawValue))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func wait(upTo seconds: Double = 3, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    // MARK: - 다른 프로그램이 고친 파일

    @Test func updateDoesNotOverwriteAnExternalEdit() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "충돌", body: "base"))
        try appendOutside("\nexternal line", to: note.id)

        #expect(throws: StoreError.conflict(note.id)) {
            try store.update(note.id) { $0.body = "base + app edit" }
        }
        // 디스크는 다른 프로그램이 쓴 그대로다.
        #expect(try diskText(note.id).hasSuffix("---\nbase\nexternal line"))
        // 앱에서 고친 내용도 버리지 않았다. 다시 써도 풀기 전에는 쓰지 않는다.
        #expect(try store.load(note.id).body == "base + app edit")
        #expect(throws: StoreError.conflict(note.id)) { try store.update(note.id) { $0.title = "다시" } }
        #expect(try diskText(note.id).hasSuffix("---\nbase\nexternal line"))
    }

    @Test func conflictCanBeResolvedKeepingEitherSide() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }
        defer { observation.cancel() }

        let mine = try store.create(NoteDraft(body: "base"))
        try appendOutside("\nexternal line", to: mine.id)
        #expect(throws: StoreError.conflict(mine.id)) { try store.update(mine.id) { $0.body = "mine" } }
        #expect(try store.resolveConflict(mine.id, keeping: .mine).body == "mine")
        #expect(try diskText(mine.id).hasSuffix("---\nmine"))

        let disk = try store.create(NoteDraft(body: "base"))
        try appendOutside("\nexternal line", to: disk.id)
        #expect(throws: StoreError.conflict(disk.id)) { try store.update(disk.id) { $0.body = "mine" } }
        #expect(try store.resolveConflict(disk.id, keeping: .disk).body == "base\nexternal line")
        #expect(try diskText(disk.id).hasSuffix("---\nbase\nexternal line"))
        #expect(changes.contains(StoreChange(id: disk.id, kind: .updated, origin: .external)))
        // 풀고 나면 다시 고칠 수 있다.
        #expect(try store.update(disk.id) { $0.body += "\napp" }.body == "base\nexternal line\napp")
        try store.flushPendingSaves()
    }

    @Test func reloadingAfterAnExternalEditAllowsTheNextUpdate() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(body: "base"))
        try appendOutside("\nexternal line", to: note.id)

        // 편집기가 바깥 변경을 다시 읽은 뒤에 고치면 충돌이 아니다.
        let reloaded = try store.load(note.id)
        #expect(reloaded.body == "base\nexternal line")
        try store.update(note.id) { $0.body = reloaded.body + "\napp" }
        #expect(try diskText(note.id).hasSuffix("---\nbase\nexternal line\napp"))
    }

    @Test func externalEditUnderPendingAutosaveIsReportedAsConflict() async throws {
        defer { temporary.cleanUp() }
        let store = try makeStore(autosaveDelay: .milliseconds(30))
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }
        defer { observation.cancel() }

        let note = try store.create(NoteDraft(body: "base"))
        try appendOutside("\nexternal line", to: note.id)
        try store.scheduleUpdate(note.id) { $0.body = "typed" }
        #expect(await wait { changes.contains(StoreChange(id: note.id, kind: .conflict, origin: .external)) })
        #expect(try diskText(note.id).hasSuffix("---\nbase\nexternal line"))

        // 충돌 중에 더 고쳐도 내용은 쌓이고 디스크는 그대로다.
        try store.scheduleUpdate(note.id) { $0.body += "!" }
        try? await Task.sleep(for: .milliseconds(120))
        #expect(try diskText(note.id).hasSuffix("---\nbase\nexternal line"))
        #expect(try store.load(note.id).body == "typed!")
    }

    @Test func refreshReportsConflictForNotesWithUnsavedEdits() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }
        defer { observation.cancel() }

        let edited = try store.create(NoteDraft(body: "base"))
        let untouched = try store.create(NoteDraft(body: "base"))
        try store.scheduleUpdate(edited.id) { $0.body = "typed" }
        try appendOutside("\nexternal line", to: edited.id)
        try appendOutside("\nexternal line", to: untouched.id)
        changes = []
        try store.refresh()

        #expect(Set(changes) == [
            StoreChange(id: edited.id, kind: .conflict, origin: .external),
            StoreChange(id: untouched.id, kind: .updated, origin: .external),
        ])
    }

    // MARK: - 두 곳에서 같은 노트를 고침

    @Test func immediateUpdateKeepsAnotherCallersPendingAutosave() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "제목", body: "original"))

        // 편집기: 본문 자동 저장을 걸어 둔다. 노트 창: 그 사이에 색을 곧바로 바꾼다.
        try store.scheduleUpdate(note.id) { $0.body = "typed in editor" }
        let saved = try store.update(note.id) { $0.colorID = PaletteID(rawValue: "tint-2") }

        #expect(saved.body == "typed in editor")
        #expect(saved.colorID == PaletteID(rawValue: "tint-2"))
        let reloaded = try makeStore().load(note.id)
        #expect(reloaded.body == "typed in editor")
        #expect(reloaded.colorID == PaletteID(rawValue: "tint-2"))
    }

    @Test func scheduledUpdatesFromTwoCallersAreMerged() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(title: "제목", body: "original"))

        try store.scheduleUpdate(note.id) { $0.body = "typed in editor" }
        try store.scheduleUpdate(note.id) { $0.title = "새 제목" }
        try store.scheduleUpdate(note.id) { $0.reminder = Date(timeIntervalSince1970: 1_800_000_000.7) }
        let current = try store.load(note.id)
        #expect(current.body == "typed in editor")
        #expect(current.title == "새 제목")

        try store.flushPendingSaves()
        let reloaded = try makeStore().load(note.id)
        #expect(reloaded.body == "typed in editor")
        #expect(reloaded.title == "새 제목")
        #expect(reloaded.reminder == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reloaded.created == note.created)
    }

    // MARK: - 휴지통

    @Test func trashWritesThePendingAutosaveFirst() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(body: "old"))
        try store.scheduleUpdate(note.id) { $0.body = "typed just before trashing" }
        try store.moveToTrash(note.id)
        #expect(try store.listTrash().notes.first?.body == "typed just before trashing")
        #expect(try store.restoreFromTrash(note.id).body == "typed just before trashing")
    }

    @Test func lateUpdatesDoNotResurrectATrashedNote() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let note = try store.create(NoteDraft(body: "body"))
        try store.moveToTrash(note.id)

        #expect(throws: StoreError.noteNotFound(note.id)) {
            try store.scheduleUpdate(note.id) { $0.body = "late autosave" }
        }
        #expect(throws: StoreError.noteNotFound(note.id)) {
            try store.update(note.id) { $0.colorID = PaletteID(rawValue: "tint-1") }
        }
        try store.flushPendingSaves()
        #expect(!FileManager.default.fileExists(atPath: temporary.noteFile(note.id.rawValue).path))
        #expect(try store.list().notes.isEmpty)
        #expect(try store.restoreFromTrash(note.id).body == "body")
    }

    @Test func trashingOverASameNamedFileKeepsBoth() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let id = NoteID(rawValue: "twice")
        let trash = temporary.location.trashDirectory
        try Data("first".utf8).write(to: temporary.noteFile("twice"))
        try store.moveToTrash(id)
        try Data("second".utf8).write(to: temporary.noteFile("twice"))
        try store.moveToTrash(id)
        try Data("third".utf8).write(to: temporary.noteFile("twice"))
        try store.moveToTrash(id)

        // 방금 버린 것이 원래 이름을 갖고, 먼저 있던 것은 옆으로 옮겨진다.
        let bodies = Dictionary(
            uniqueKeysWithValues: try store.listTrash().notes.map { ($0.id.rawValue, $0.body) }
        )
        #expect(bodies == ["twice": "third", "twice-2": "first", "twice-3": "second"])
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("twice-2.md").path))
        #expect(try store.restoreFromTrash(id).body == "third")
        #expect(try store.restoreFromTrash(NoteID(rawValue: "twice-2")).body == "first")
    }

    // MARK: - 한꺼번에 쓰기

    @Test func flushAttemptsEveryNoteAndKeepsTheFailedOnes() throws {
        defer { temporary.cleanUp() }
        let store = try makeStore()
        let blocked = try store.create(NoteDraft(title: "막힌 노트"))
        let conflicted = try store.create(NoteDraft(title: "충돌 노트", body: "base"))
        let fine = try store.create(NoteDraft(title: "멀쩡한 노트"))
        for note in [blocked, conflicted, fine] {
            try store.scheduleUpdate(note.id) { $0.body = "pending \($0.title)" }
        }
        // 하나는 파일 자리가 폴더로 바뀌고, 하나는 다른 프로그램이 고쳤다.
        try FileManager.default.removeItem(at: temporary.noteFile(blocked.id.rawValue))
        try FileManager.default.createDirectory(
            at: temporary.noteFile(blocked.id.rawValue), withIntermediateDirectories: true
        )
        try appendOutside("\nexternal line", to: conflicted.id)

        let expected = [
            SaveFailure(
                id: blocked.id, title: "막힌 노트",
                error: .unreadableFile(temporary.noteFile(blocked.id.rawValue))
            ),
            SaveFailure(id: conflicted.id, title: "충돌 노트", error: .conflict(conflicted.id)),
        ].sorted { $0.id.rawValue < $1.id.rawValue }
        #expect(throws: StoreError.pendingSavesFailed(expected)) { try store.flushPendingSaves() }

        // 실패한 것과 상관없이 나머지는 썼다.
        #expect(try diskText(fine.id).hasSuffix("---\npending 멀쩡한 노트"))
        // 실패한 것은 남아 있어 다시 시도된다.
        #expect(try store.load(blocked.id).body == "pending 막힌 노트")
        #expect(try store.load(conflicted.id).body == "pending 충돌 노트")
        #expect(throws: StoreError.pendingSavesFailed(expected)) { try store.flushPendingSaves() }

        // 막힌 까닭이 없어지면 다음 시도에서 써진다.
        try FileManager.default.removeItem(at: temporary.noteFile(blocked.id.rawValue))
        try store.resolveConflict(conflicted.id, keeping: .mine)
        #expect(throws: StoreError.pendingSavesFailed([
            SaveFailure(id: blocked.id, title: "막힌 노트", error: .noteNotFound(blocked.id)),
        ])) { try store.flushPendingSaves() }
        #expect(try diskText(conflicted.id).hasSuffix("---\npending 충돌 노트"))
    }
}
