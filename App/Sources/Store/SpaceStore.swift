import Foundation
import Models

/// 스페이스 목록. `stateDirectory/spaces.json`에 순서대로 둔다.
@MainActor
public final class SpaceStore {
    private let file: JSONFile<[Space]>
    public private(set) var spaces: [Space]
    public let imageDirectory: URL
    private let observers = StateObservers()
    /// 저장된 파일을 읽지 못해 빈 목록으로 시작했으면 그 설명. 앱이 켤 때 모아서 기록한다.
    public let loadWarning: String?

    /// 파일이 망가져 있으면 옆으로 옮겨 두고(`spaces.json.corrupt`) 빈 목록으로 시작한다.
    public init(location: StoreLocation) throws {
        imageDirectory = location.stateDirectory.appendingPathComponent("space-images", isDirectory: true)
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("spaces.json"))
        let loaded = try file.loadRecovering()
        spaces = loaded.value ?? []
        loadWarning = loaded.warning
    }

    public func space(for id: SpaceID) -> Space? {
        spaces.first { $0.id == id }
    }

    public enum MutationError: Error { case emptyName, missingSpace }

    @discardableResult public func create(name: String, icon: SpaceIcon = .none) throws -> Space {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MutationError.emptyName }
        let space = Space(id: .make(), name: name, icon: icon)
        try replace(with: spaces + [space])
        return space
    }

    public func update(_ id: SpaceID, _ change: (inout Space) -> Void) throws {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw MutationError.missingSpace }
        var next = spaces
        change(&next[index])
        next[index].name = next[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next[index].name.isEmpty else { throw MutationError.emptyName }
        try replace(with: next)
    }

    /// 노트는 지우지 않는다. 활성 노트의 연결을 먼저 해제하고 마지막에 스페이스를 지운다.
    /// 중간 저장이 실패하면 스페이스는 남고 오류를 돌려준다. 다시 시도하면 남은 연결만 처리한다.
    /// 휴지통은 변경하지 않고, 복원 시 없어진 스페이스 연결을 해제한다.
    public func delete(_ id: SpaceID, notes: any NoteStoring) throws {
        guard space(for: id) != nil else { throw MutationError.missingSpace }
        let listing = try notes.list()
        if let failure = listing.failures.first { throw failure.error }
        for note in listing.notes where note.spaceID == id {
            try notes.update(note.id) { $0.spaceID = nil }
        }
        try replace(with: spaces.filter { $0.id != id })
    }

    /// 목록을 통째로 바꾸고 곧바로 파일에 쓴다.
    public func replace(with newSpaces: [Space]) throws {
        try file.save(newSpaces)
        let changed = newSpaces != spaces
        spaces = newSpaces
        if changed { observers.notify() }
    }

    /// 목록이 바뀔 때마다(파일에 쓴 뒤) 불린다. 돌려받은 값을 들고 있는 동안만 알림이 온다.
    /// 같은 목록으로 바꾸면 알리지 않는다.
    public func observe(_ handler: @escaping @MainActor () -> Void) -> StoreObservation {
        observers.add(handler)
    }
}
