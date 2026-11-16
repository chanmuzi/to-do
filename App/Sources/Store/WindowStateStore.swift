import Foundation
import Models

/// 노트 창의 위치·크기·핀·열림 상태. 노트 파일과 따로 `stateDirectory/windows.json`에 둔다(D-003).
@MainActor
public final class WindowStateStore {
    private let file: JSONFile<[String: NoteWindowState]>
    private var states: [String: NoteWindowState]
    private let observers = StateObservers()
    /// 저장된 파일을 읽지 못해 빈 상태로 시작했으면 그 설명. 앱이 켤 때 모아서 기록한다.
    public let loadWarning: String?

    /// 파일이 망가져 있으면 옆으로 옮겨 두고(`windows.json.corrupt`) 빈 상태로 시작한다.
    public init(location: StoreLocation) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("windows.json"))
        let loaded = try file.loadRecovering()
        states = loaded.value ?? [:]
        loadWarning = loaded.warning
    }

    public var all: [NoteID: NoteWindowState] {
        Dictionary(uniqueKeysWithValues: states.map { (NoteID(rawValue: $0.key), $0.value) })
    }

    public func state(for id: NoteID) -> NoteWindowState? {
        states[id.rawValue]
    }

    /// 바꾸고 곧바로 파일에 쓴다.
    public func set(_ state: NoteWindowState, for id: NoteID) throws {
        try commit(states.merging([id.rawValue: state]) { _, new in new })
    }

    public func remove(_ id: NoteID) throws {
        try commit(states.filter { $0.key != id.rawValue })
    }

    /// 창 상태가 바뀔 때마다(파일에 쓴 뒤) 불린다. 돌려받은 값을 들고 있는 동안만 알림이 온다.
    /// 값이 그대로인 `set`은 쓰지도 알리지도 않는다. 무엇이 바뀌었는지는 `all`, `state(for:)`로 다시 읽는다.
    public func observe(_ handler: @escaping @MainActor () -> Void) -> StoreObservation {
        observers.add(handler)
    }

    private func commit(_ newStates: [String: NoteWindowState]) throws {
        guard newStates != states else { return }
        try file.save(newStates)
        states = newStates
        observers.notify()
    }
}
