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

        let note = try store.create(NoteDraft(title: "하나"))
        try store.update(note.id) { $0.body = "고침" }
        try store.update(note.id) { $0.body = "고침" } // 내용이 같으면 알리지 않는다.
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
        let note = try store.create(NoteDraft(title: "자동 저장"))
        var updates = 0
        let observation = store.observe { if $0.kind == .updated { updates += 1 } }
        defer { observation.cancel() }

        for text in ["가", "가나", "가나다"] {
            try store.scheduleUpdate(note.id) { $0.body = text }
        }
        // 아직 디스크에는 없다. 저장소의 지금 값에는 있다.
        #expect(try String(contentsOf: temporary.noteFile(note.id.rawValue), encoding: .utf8).hasSuffix("---\n"))
        #expect(try store.load(note.id).body == "가나다")
        #expect(try store.list().notes.first?.body == "가나다")
        #expect(await wait { updates > 0 })
        #expect(updates == 1)
        #expect(try String(contentsOf: temporary.noteFile(note.id.rawValue), encoding: .utf8).hasSuffix("---\n가나다"))
    }

    @Test func flushWritesPendingSavesImmediately() throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .seconds(60))
        let note = try store.create(NoteDraft())
        try store.scheduleUpdate(note.id) { $0.body = "끝내기 직전" }
        try store.flushPendingSaves()
        #expect(try FileNoteStore(location: temporary.location).load(note.id).body == "끝내기 직전")
    }

    @Test func failedScheduledSaveIsReported() async throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(location: temporary.location, autosaveDelay: .milliseconds(20))
        var failures: [StoreChange] = []
        let observation = store.observe { change in
            if case .saveFailed = change.kind { failures.append(change) }
        }
        defer { observation.cancel() }

        // 고치는 사이에 노트 파일 자리가 폴더로 바뀌면 쓸 수 없다.
        let note = try store.create(NoteDraft(title: "막힌 노트"))
        try store.scheduleUpdate(note.id) { $0.body = "쓰지 못할 글" }
        try FileManager.default.removeItem(at: temporary.noteFile(note.id.rawValue))
        try FileManager.default.createDirectory(
            at: temporary.noteFile(note.id.rawValue), withIntermediateDirectories: true
        )
        #expect(await wait { !failures.isEmpty })
        #expect(failures.first?.id == note.id)
        // 고친 내용은 버리지 않고 들고 있다.
        #expect(try store.load(note.id).body == "쓰지 못할 글")
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

    /// 계속 고치는 중이어도 첫 변경 뒤 최대 대기가 지나면 디스크에 쓴다.
    @Test func continuousEditingStillReachesDiskWithinTheMaximumWait() async throws {
        defer { temporary.cleanUp() }
        let store = try FileNoteStore(
            location: temporary.location, autosaveDelay: .seconds(60), autosaveMaxWait: .milliseconds(200)
        )
        let note = try store.create(NoteDraft(title: "계속 치는 중"))
        var updates = 0
        let observation = store.observe { if $0.kind == .updated { updates += 1 } }
        defer { observation.cancel() }

        // 디바운스(60초)보다 훨씬 촘촘하게 계속 고친다. 디바운스만으로는 영영 쓰지 않는다.
        var typed = ""
        let deadline = Date().addingTimeInterval(3)
        while updates == 0, Date() < deadline {
            typed += "가"
            try store.scheduleUpdate(note.id) { $0.body = typed }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(updates >= 1)
        let onDisk = try String(contentsOf: temporary.noteFile(note.id.rawValue), encoding: .utf8)
        #expect(onDisk.hasSuffix("가"))
    }

    /// 저장소를 버리면 폴더 감시가 쥔 디스크립터도 닫힌다.
    @Test func droppedStoresReleaseTheirDirectoryDescriptors() async throws {
        defer { temporary.cleanUp() }
        let directory = temporary.location.notesDirectory.lastPathComponent
        let marker = "/\(temporary.root.lastPathComponent)/\(directory)"
        func openDescriptors() -> Int {
            (0..<getdtablesize()).filter { descriptor in
                var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return false }
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    .hasSuffix(marker)
            }.count
        }

        do {
            let alive = try FileNoteStore(location: temporary.location)
            #expect(openDescriptors() == 1)
            _ = alive
        }
        for _ in 0..<50 { _ = try FileNoteStore(location: temporary.location) }
        #expect(await wait { openDescriptors() == 0 })
    }
}
