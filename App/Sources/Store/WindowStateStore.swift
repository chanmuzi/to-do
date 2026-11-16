import Foundation
import Models

/// 노트 창의 위치·크기·핀·열림 상태. 노트 파일과 따로 `stateDirectory/windows.json`에 둔다(D-003).
@MainActor
public final class WindowStateStore {
    private let file: JSONFile<[String: NoteWindowState]>
    private var states: [String: NoteWindowState]

    public init(location: StoreLocation) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("windows.json"))
        states = try file.load() ?? [:]
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

    private func commit(_ newStates: [String: NoteWindowState]) throws {
        guard newStates != states else { return }
        try file.save(newStates)
        states = newStates
    }
}
