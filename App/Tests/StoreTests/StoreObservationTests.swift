import Foundation
import Testing
import Models
@testable import Store

@Suite @MainActor struct StoreObservationTests {
    let temporary = TemporaryStore()

    /// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다.
    private func wait(upTo seconds: Double = 3, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func localMutationsAreReported() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location)
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }

        var note = try store.create(NoteDraft(title: "하나"))
        note.body = "고침"
        try store.save(note)
        try store.save(note) // 내용이 같으면 알리지 않는다.
        try store.moveToTrash(note.id)

        #expect(changes == [
            StoreChange(id: note.id, kind: .created, origin: .local),
            StoreChange(id: note.id, kind: .updated, origin: .local),
            StoreChange(id: note.id, kind: .removed, origin: .local),
        ])

        observation.cancel()
        _ = try store.create(NoteDraft())
        #expect(changes.count == 3)
    }

    @Test func droppingTheObservationStopsNotifications() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location)
        var count = 0
        var observation: StoreObservation? = store.observe { _ in count += 1 }
        _ = try store.create(NoteDraft())
        #expect(count == 1)
        _ = observation
        observation = nil
        _ = try store.create(NoteDraft())
        #expect(count == 1)
    }

    @Test func scheduledSaveIsDebouncedAndWritesTheLatest() async throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .milliseconds(80))
        var note = try store.create(NoteDraft(title: "자동 저장"))
        var updates = 0
        let observation = store.observe { if $0.kind == .updated { updates += 1 } }
        defer { observation.cancel() }

        for text in ["가", "가나", "가나다"] {
            note.body = text
            store.scheduleSave(note)
        }
        // 아직 디스크에는 없다.
        #expect(try store.load(note.id).body == "")
        #expect(await wait { updates > 0 })
        #expect(updates == 1)
        #expect(try store.load(note.id).body == "가나다")
    }

    @Test func flushWritesPendingSavesImmediately() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .seconds(60))
        var note = try store.create(NoteDraft())
        note.body = "끝내기 직전"
        store.scheduleSave(note)
        try store.flushPendingSaves()
        #expect(try store.load(note.id).body == "끝내기 직전")
    }

    @Test func failedScheduledSaveIsReported() async throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .milliseconds(20))
        var failures: [StoreChange] = []
        let observation = store.observe { change in
            if case .saveFailed = change.kind { failures.append(change) }
        }
        defer { observation.cancel() }

        // 노트 파일 자리에 폴더가 있으면 쓸 수 없다.
        let note = Note(id: NoteID(rawValue: "blocked"), created: Date(), modified: Date())
        try FileManager.default.createDirectory(
            at: temporary.noteFile("blocked"), withIntermediateDirectories: true
        )
        store.scheduleSave(note)
        #expect(await wait { !failures.isEmpty })
        #expect(failures.first?.id == note.id)
    }

    @Test func externalChangesAreReported() async throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location)
        var changes: [StoreChange] = []
        let observation = store.observe { changes.append($0) }
        defer { observation.cancel() }
        let id = NoteID(rawValue: "outside")

        // 다른 프로그램이 파일을 만든다(폴더 감시가 잡는다).
        try Data("밖에서".utf8).write(to: temporary.noteFile("outside"), options: .atomic)
        #expect(await wait { changes.contains(StoreChange(id: id, kind: .created, origin: .external)) })

        // 제자리에서 고친 것은 refresh()가 잡는다.
        let handle = try FileHandle(forWritingTo: temporary.noteFile("outside"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" 고침".utf8))
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: temporary.noteFile("outside").path
        )
        try store.refresh()
        #expect(changes.contains(StoreChange(id: id, kind: .updated, origin: .external)))

        try FileManager.default.removeItem(at: temporary.noteFile("outside"))
        #expect(await wait { changes.contains(StoreChange(id: id, kind: .removed, origin: .external)) })
    }
}
