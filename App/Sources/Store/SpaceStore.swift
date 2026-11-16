import Foundation
import Models

/// 스페이스 목록. `stateDirectory/spaces.json`에 순서대로 둔다.
@MainActor
public final class SpaceStore {
    private let file: JSONFile<[Space]>
    public private(set) var spaces: [Space]
    private let observers = StateObservers()
    /// 저장된 파일을 읽지 못해 빈 목록으로 시작했으면 그 설명. 앱이 켤 때 모아서 기록한다.
    public let loadWarning: String?

    /// 파일이 망가져 있으면 옆으로 옮겨 두고(`spaces.json.corrupt`) 빈 목록으로 시작한다.
    public init(location: StoreLocation) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("spaces.json"))
        let loaded = try file.loadRecovering()
        spaces = loaded.value ?? []
        loadWarning = loaded.warning
    }

    public func space(for id: SpaceID) -> Space? {
        spaces.first { $0.id == id }
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
