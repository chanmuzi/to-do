import Foundation
import Models
import Store
import Testing

/// 창 상태의 쓰기를 한데 모으는지(`writeDelay`): 잇단 변경이 파일 전체를 여러 번 다시 쓰지 않고,
/// 읽는 쪽은 언제나 지금 값을 보며, `flush()`가 파일까지 맞춘다.
@Suite @MainActor struct WindowStateCoalescingTests {
    let temporary = TemporaryStore()
    private let id = NoteID(rawValue: "n1")

    private var fileURL: URL { temporary.location.stateDirectory.appendingPathComponent("windows.json") }

    /// 키 창이 다섯 번 되어 연 때가 다섯 번 바뀌어도 파일은 한 번만 쓰인다. 그사이에도 읽는 값과 알림은 바로 온다.
    @Test func burstOfChangesIsWrittenOnce() async throws {
        defer { temporary.cleanUp() }
        let store = try WindowStateStore(location: temporary.location, writeDelay: .milliseconds(40))
        var announced = 0
        let observation = store.observe { announced += 1 }
        defer { observation.cancel() }

        for second in 1...5 {
            try store.set(
                NoteWindowState(isOpen: true, lastOpened: Date(timeIntervalSince1970: Double(second))), for: id
            )
        }
        #expect(store.writeCount == 0)
        #expect(announced == 5)
        #expect(store.state(for: id)?.lastOpened == Date(timeIntervalSince1970: 5))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let deadline = Date().addingTimeInterval(3)
        while store.writeCount == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.writeCount == 1)
        let reloaded = try WindowStateStore(location: temporary.location)
        #expect(reloaded.state(for: id)?.lastOpened == Date(timeIntervalSince1970: 5))
    }

    /// `flush()`는 기다리지 않고 지금 쓴다. 쓸 것이 없으면 쓰지 않고, 미뤄 둔 쓰기가 뒤늦게 한 번 더 쓰지도 않는다.
    @Test func flushWritesPendingChangesNow() async throws {
        defer { temporary.cleanUp() }
        let store = try WindowStateStore(location: temporary.location, writeDelay: .milliseconds(40))
        try store.flush()
        #expect(store.writeCount == 0)

        try store.set(NoteWindowState(isPinned: false, isOpen: true), for: id)
        try store.flush()
        #expect(store.writeCount == 1)
        #expect(try WindowStateStore(location: temporary.location).state(for: id)?.isPinned == false)

        try store.flush()
        try await Task.sleep(for: .milliseconds(120))
        #expect(store.writeCount == 1)

        try store.remove(id)
        try store.flush()
        #expect(try WindowStateStore(location: temporary.location).all.isEmpty)
    }

    /// 미뤄 둔 쓰기가 실패하면 숨기지 않고 알리고, 값은 남아 있다가 문제가 풀린 뒤의 `flush()`로 쓰인다.
    @Test func failedDeferredWriteIsReportedAndRetried() async throws {
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: temporary.location.stateDirectory.path
            )
            temporary.cleanUp()
        }
        let store = try WindowStateStore(location: temporary.location, writeDelay: .milliseconds(20))
        var failures: [Error] = []
        store.onWriteFailure = { failures.append($0) }
        let directory = temporary.location.stateDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        try store.set(NoteWindowState(isOpen: true), for: id)
        let deadline = Date().addingTimeInterval(3)
        while failures.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(failures.count == 1)
        #expect(store.writeCount == 0)
        #expect(store.state(for: id) == NoteWindowState(isOpen: true))
        #expect(throws: (any Error).self) { try store.flush() }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try store.flush()
        #expect(store.writeCount == 1)
        #expect(try WindowStateStore(location: temporary.location).state(for: id) == NoteWindowState(isOpen: true))
    }

    /// 미루지 않는 저장소(기본)는 전처럼 바꿀 때마다 곧바로 쓴다.
    @Test func immediateStoreWritesEveryChange() throws {
        defer { temporary.cleanUp() }
        let store = try WindowStateStore(location: temporary.location)
        try store.set(NoteWindowState(isOpen: true), for: id)
        try store.set(NoteWindowState(isOpen: false), for: id)
        #expect(store.writeCount == 2)
        #expect(try WindowStateStore(location: temporary.location).state(for: id)?.isOpen == false)
    }
}
