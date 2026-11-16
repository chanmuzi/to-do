import Foundation
import Models

/// 스페이스 목록. `stateDirectory/spaces.json`에 순서대로 둔다.
@MainActor
public final class SpaceStore {
    private let file: JSONFile<[Space]>
    public private(set) var spaces: [Space]

    public init(location: StoreLocation) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("spaces.json"))
        spaces = try file.load() ?? []
    }

    public func space(for id: SpaceID) -> Space? {
        spaces.first { $0.id == id }
    }

    /// 목록을 통째로 바꾸고 곧바로 파일에 쓴다.
    public func replace(with newSpaces: [Space]) throws {
        try file.save(newSpaces)
        spaces = newSpaces
    }
}
