import Foundation
import Models
import Testing

@Suite struct LibraryPreferencesTests {
    @Test func emptyObjectUsesDefaults() throws {
        #expect(try JSONDecoder().decode(LibraryPreferences.self, from: Data("{}".utf8)) == LibraryPreferences())
    }

    @Test(arguments: ["visibleViews", "opensLastSelection", "lastSelection", "pinnedIcons", "recentIcons", "images"])
    func missingKeyDefaultsWithoutDiscardingOtherValues(key: String) throws {
        var saved = LibraryPreferences()
        saved.setVisible(.today, false)
        saved.setVisible(.floating, false)
        saved.setVisible(.reminders, true)
        saved.opensLastSelection = false
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
        case "visibleViews": for view in LibrarySelection.views { expected.setVisible(view, defaults.visibleViews.contains(view)) }
        case "opensLastSelection": expected.opensLastSelection = defaults.opensLastSelection
        case "lastSelection": expected.lastSelection = defaults.lastSelection
        case "pinnedIcons": expected.pinnedIcons = defaults.pinnedIcons
        case "recentIcons": expected.recentIcons = defaults.recentIcons
        case "images": expected.images = defaults.images
        default: Issue.record("알 수 없는 설정 키: \(key)")
        }
        #expect(decoded == expected)
    }

    @Test func migratesLegacyOrderAndOpeningChoiceWithoutPromotingIt() throws {
        let old = Data(#"{"visibleViews":[{"all":{}},{"today":{}}],"openingView":{"all":{}}}"#.utf8)
        var prefs = try JSONDecoder().decode(LibraryPreferences.self, from: old)
        #expect(prefs.viewOrder == LibrarySelection.views)
        #expect(prefs.visibleViews == [.today, .all])
        #expect(!prefs.opensLastSelection)
        prefs.moveView(.all, to: .today, visibleOnly: true)
        #expect(prefs.viewOrder == [.all, .floating, .today, .reminders])
        prefs.setVisible(.floating, true)
        #expect(prefs.visibleViews == [.all, .floating, .today])
        #expect(try JSONDecoder().decode(LibraryPreferences.self, from: JSONEncoder().encode(prefs)) == prefs)
    }

    @Test func invalidValueIsNotSilentlyReplacedByDefault() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LibraryPreferences.self, from: Data(#"{"images":42}"#.utf8))
        }
    }
}
