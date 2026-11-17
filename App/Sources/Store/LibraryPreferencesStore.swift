import Foundation
import Models

@MainActor
public final class LibraryPreferencesStore {
    private let file: JSONFile<LibraryPreferences>
    public private(set) var value: LibraryPreferences
    public let loadWarning: String?
    public init(location: StoreLocation) throws {
        file = JSONFile(url: location.stateDirectory.appendingPathComponent("library.json"))
        let loaded = try file.loadRecovering()
        value = loaded.value ?? LibraryPreferences()
        loadWarning = loaded.warning
    }
    public func update(_ change: (inout LibraryPreferences) -> Void) throws {
        var next = value
        change(&next)
        try file.save(next)
        value = next
    }
}
