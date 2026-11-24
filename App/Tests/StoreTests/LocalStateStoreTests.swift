import Foundation
import Testing
import Models
import Store

@Suite @MainActor struct LocalStateStoreTests {
    let temporary = TemporaryStore()

    @Test func windowStatePersistsOutsideTheNotesFiles() throws {
        defer { temporary.cleanUp() }
        let id = NoteID(rawValue: "n1")
        let state = NoteWindowState(
            frame: WindowFrame(x: 100, y: 200, width: 340, height: 180), isPinned: false, isOpen: true
        )
        let store = try WindowStateStore(location: temporary.location)
        #expect(store.state(for: id) == nil)
        try store.set(state, for: id)
        try store.set(NoteWindowState(), for: NoteID(rawValue: "n2"))

        let reloaded = try WindowStateStore(location: temporary.location)
        #expect(reloaded.state(for: id) == state)
        #expect(reloaded.all.count == 2)
        #expect(FileManager.default.fileExists(
            atPath: temporary.location.stateDirectory.appendingPathComponent("windows.json").path
        ))

        try reloaded.remove(id)
        #expect(try WindowStateStore(location: temporary.location).state(for: id) == nil)
    }

    @Test func oldWindowFramesBecomePreferredHeightsAndNewAutomaticFramesStayAutomatic() throws {
        defer { temporary.cleanUp() }
        let folder = temporary.location.stateDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let frame = WindowFrame(x: 20, y: 30, width: 340, height: 420)
        let file = folder.appendingPathComponent("windows.json")
        try Data(#"{"old":{"isPinned":false,"isOpen":false,"frame":{"x":20,"y":30,"width":340,"height":420}}}"#.utf8).write(to: file)
        let id = NoteID(rawValue: "old")
        let store = try WindowStateStore(location: temporary.location)
        var old = try #require(store.state(for: id))
        #expect(old.heightPreference == .fixed(420))
        old.frame?.height = 300
        try store.set(old, for: id)
        let new = NoteID(rawValue: "automatic")
        try store.set(NoteWindowState(frame: frame), for: new)
        let reloaded = try WindowStateStore(location: temporary.location)
        #expect(reloaded.state(for: id)?.heightPreference == .fixed(420))
        #expect(reloaded.state(for: new)?.heightPreference == .followSetting)
    }

    @Test func spacesPersistInOrder() throws {
        defer { temporary.cleanUp() }
        let spaces = [
            Space(id: SpaceID(rawValue: "work"), name: "회사", icon: .symbol(name: "briefcase", colorID: nil)),
            Space(id: SpaceID(rawValue: "home"), name: "개인", icon: .emoji("🏠")),
        ]
        let store = try SpaceStore(location: temporary.location)
        #expect(store.spaces.isEmpty)
        try store.replace(with: spaces)

        let reloaded = try SpaceStore(location: temporary.location)
        #expect(reloaded.spaces == spaces)
        #expect(reloaded.space(for: SpaceID(rawValue: "home"))?.name == "개인")
    }

    /// 창 상태가 바뀌면 알린다. 값이 그대로면 알리지 않고, 표를 놓으면 알림이 멈춘다.
    @Test func windowStateChangesAreAnnounced() throws {
        defer { temporary.cleanUp() }
        let id = NoteID(rawValue: "n1")
        let store = try WindowStateStore(location: temporary.location)
        var seen: [NoteWindowState?] = []
        var observation: StoreObservation? = store.observe { seen.append(store.state(for: id)) }

        try store.set(NoteWindowState(isOpen: true), for: id)
        // 알림을 받을 때는 이미 새 값이 읽힌다.
        #expect(seen == [NoteWindowState(isOpen: true)])
        try store.set(NoteWindowState(isOpen: true), for: id)
        #expect(seen.count == 1)
        try store.set(NoteWindowState(isPinned: false, isOpen: true), for: id)
        try store.remove(id)
        #expect(seen.count == 3)
        #expect(seen.last == .some(nil))
        try store.remove(id)
        #expect(seen.count == 3)

        observation?.cancel()
        observation = nil
        try store.set(NoteWindowState(), for: id)
        #expect(seen.count == 3)
    }

    /// 마지막으로 연 때는 창 상태와 함께 남고, 그것 없이 적힌 예전 파일도 읽힌다.
    @Test func lastOpenedTimePersistsAndOldFilesStillLoad() throws {
        defer { temporary.cleanUp() }
        let id = NoteID(rawValue: "n1")
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try WindowStateStore(location: temporary.location)
        try store.set(NoteWindowState(isOpen: true, lastOpened: opened), for: id)
        #expect(try WindowStateStore(location: temporary.location).state(for: id)?.lastOpened == opened)

        let file = temporary.location.stateDirectory.appendingPathComponent("windows.json")
        try Data(#"{"old":{"isOpen":true,"isPinned":false}}"#.utf8).write(to: file)
        let reloaded = try WindowStateStore(location: temporary.location)
        #expect(reloaded.loadWarning == nil)
        #expect(reloaded.state(for: NoteID(rawValue: "old")) == NoteWindowState(isPinned: false, isOpen: true))
    }

    @Test func spaceListChangesAreAnnounced() throws {
        defer { temporary.cleanUp() }
        let work = Space(id: SpaceID(rawValue: "work"), name: "회사", icon: .emoji("💼"))
        let store = try SpaceStore(location: temporary.location)
        var counts: [Int] = []
        let observation = store.observe { counts.append(store.spaces.count) }

        try store.replace(with: [work])
        try store.replace(with: [work])
        try store.replace(with: [])
        #expect(counts == [1, 0])
        observation.cancel()
        try store.replace(with: [work])
        #expect(counts == [1, 0])
    }

    /// 잘린 상태 파일은 앱을 막지 않는다. 빈 상태로 시작하고 원래 파일은 옆에 남긴다.
    @Test func corruptStateFilesAreSetAsideInsteadOfBlocking() throws {
        defer { temporary.cleanUp() }
        let directory = temporary.location.stateDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let truncated = Data("{\"n1\":{\"isOpen\":tr".utf8)
        try truncated.write(to: directory.appendingPathComponent("windows.json"))
        try truncated.write(to: directory.appendingPathComponent("spaces.json"))

        let windows = try WindowStateStore(location: temporary.location)
        #expect(windows.all.isEmpty)
        #expect(windows.loadWarning?.contains("windows.json.corrupt") == true)
        #expect(try Data(contentsOf: directory.appendingPathComponent("windows.json.corrupt")) == truncated)

        let spaces = try SpaceStore(location: temporary.location)
        #expect(spaces.spaces.isEmpty)
        #expect(spaces.loadWarning?.contains("spaces.json.corrupt") == true)
        #expect(try Data(contentsOf: directory.appendingPathComponent("spaces.json.corrupt")) == truncated)

        // 새로 저장할 수 있고, 다음에는 경고 없이 읽힌다.
        try windows.set(NoteWindowState(), for: NoteID(rawValue: "n1"))
        let reloaded = try WindowStateStore(location: temporary.location)
        #expect(reloaded.loadWarning == nil)
        #expect(reloaded.all.count == 1)

        // 또 망가지면 먼저 옮겨 둔 파일을 덮지 않는다.
        try Data("[".utf8).write(to: directory.appendingPathComponent("windows.json"))
        #expect(try WindowStateStore(location: temporary.location).loadWarning?.contains("windows.json.corrupt-2") == true)
        #expect(try Data(contentsOf: directory.appendingPathComponent("windows.json.corrupt")) == truncated)
    }

    @Test func locationsStayInsideTheGivenDirectory() throws {
        let notes = URL(fileURLWithPath: "/tmp/fn-example/notes", isDirectory: true)
        let isolated = StoreLocation.isolated(notesDirectory: notes)
        #expect(isolated.trashDirectory.path == "/tmp/fn-example/notes/.trash")
        #expect(isolated.stateDirectory.path == "/tmp/fn-example/notes/.state")

        let fromEnvironment = try StoreLocation.standard(
            environment: [StoreLocation.environmentKey: "/tmp/fn-example/notes"]
        )
        #expect(fromEnvironment == isolated)

        let standard = try StoreLocation.standard(environment: [:])
        #expect(standard.notesDirectory.path.hasSuffix("/Library/Application Support/FloatingNotes/notes"))
        #expect(standard.stateDirectory.path.hasSuffix("/Library/Application Support/FloatingNotes/state"))
    }
}
