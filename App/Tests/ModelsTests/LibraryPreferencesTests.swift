import Foundation
import Models
import Testing

@Suite struct LibraryPreferencesTests {
    @Test func emptyObjectUsesDefaults() throws {
        #expect(try JSONDecoder().decode(LibraryPreferences.self, from: Data("{}".utf8)) == LibraryPreferences())
    }

    @Test(arguments: ["visibleViews", "openingView", "lastSelection", "pinnedIcons", "recentIcons", "images"])
    func missingKeyDefaultsWithoutDiscardingOtherValues(key: String) throws {
        var saved = LibraryPreferences()
        saved.visibleViews = [.all, .reminders]
        saved.openingView = .all
        saved.lastSelection = .trash
        saved.pinnedIcons = [.emoji("🏠")]
        saved.recentIcons = [.customSymbol(name: "star", hex: "#125678")]
        saved.images = ["custom.gif"]
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        object.removeValue(forKey: key)
        let decoded = try JSONDecoder().decode(LibraryPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        let defaults = LibraryPreferences()
        var expected = saved
        switch key {
        case "visibleViews": expected.visibleViews = defaults.visibleViews
        case "openingView": expected.openingView = defaults.openingView
        case "lastSelection": expected.lastSelection = defaults.lastSelection
        case "pinnedIcons": expected.pinnedIcons = defaults.pinnedIcons
        case "recentIcons": expected.recentIcons = defaults.recentIcons
        case "images": expected.images = defaults.images
        default: Issue.record("알 수 없는 설정 키: \(key)")
        }
        #expect(decoded == expected)
    }

    @Test func invalidValueIsNotSilentlyReplacedByDefault() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LibraryPreferences.self, from: Data(#"{"images":42}"#.utf8))
        }
    }
}
