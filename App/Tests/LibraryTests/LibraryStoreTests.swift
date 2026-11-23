import AppKit
import Foundation
import Models
import Routing
import SpaceIcons
import Store
import Testing
import Theme
@testable import Library

@Suite struct LibraryStoreTests {
    func fixture() throws -> (URL, StoreLocation, FileNoteStore, SpaceStore) {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("library-tests-\(UUID().uuidString)")
        let location = StoreLocation.isolated(notesDirectory: root)
        return (root, location, try FileNoteStore(location: location), try SpaceStore(location: location))
    }
    @Test func spaceCRUDKeepsNotesAndSurvivesReload() throws {
        let (root, location, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let work = try spaces.create(name: " 회사 ", icon: .symbol(name: "briefcase", colorID: nil))
        let note = try notes.create(NoteDraft(title: "보존", body: "원문", spaceID: work.id))
        try spaces.update(work.id) { $0.name = "업무"; $0.icon = .emoji("🏠") }
        #expect(try SpaceStore(location: location).space(for: work.id)?.name == "업무")
        try spaces.delete(work.id, notes: notes)
        #expect(try notes.load(note.id).body == "원문")
        #expect(try notes.load(note.id).spaceID == nil)
        #expect(try SpaceStore(location: location).spaces.isEmpty)
    }
    @Test func emptyNameRejectedWithoutMutation() throws {
        let (root, _, _, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SpaceStore.MutationError.self) { try spaces.create(name: " \n ") }
        #expect(spaces.spaces.isEmpty)
    }
    @Test func legacySpaceJSONRemainsReadable() throws {
        let data = Data(#"[{"id":"work","name":"회사","icon":{"symbol":{"name":"briefcase","colorID":"tint-2"}}},{"id":"home","name":"집","icon":{"emoji":{"_0":"🏠"}}},{"id":"dev","name":"개발","icon":{"image":{"_0":"terminal"}}}]"#.utf8)
        let values = try JSONDecoder().decode([Space].self, from: data)
        #expect(values[0].icon == .symbol(name: "briefcase", colorID: .init(rawValue: "tint-2")))
        #expect(values[1].icon == .emoji("🏠"))
        #expect(values[2].icon == .image("terminal"))
        #expect(try JSONDecoder().decode([Space].self, from: JSONEncoder().encode(values)) == values)
    }
    @Test(arguments: [SpaceIcon.none, .customSymbol(name: "star", hex: "#125678"), .image("custom.gif")])
    func newIconCasesRoundTrip(icon: SpaceIcon) throws {
        #expect(try JSONDecoder().decode(SpaceIcon.self, from: JSONEncoder().encode(icon)) == icon)
    }
    @Test(arguments: [LibrarySelection.trash, .all])
    func restoresTrashedNoteAfterSpaceDeletedAndOpensIt(selection: LibrarySelection) throws {
        let (root, location, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let space = try spaces.create(name: "회사")
        let note = try notes.create(NoteDraft(title: "되돌리기", spaceID: space.id))
        try notes.moveToTrash(note.id); try spaces.delete(space.id, notes: notes)
        var routes: [Route] = []
        let model = LibraryModel(theme: try Theme.bundled(), notes: notes, spaces: spaces,
            windows: try WindowStateStore(location: location), preferences: try LibraryPreferencesStore(location: location),
            router: RouteDispatcher { routes.append($0) })
        model.select(selection); model.open(try #require(model.index.trash.first))
        #expect(try notes.load(note.id).spaceID == nil)
        #expect(routes == [.openNote(note.id)])
        #expect(model.index.trash.isEmpty)
        #expect(model.error == nil)
    }
    @Test func reminderOpensWhileTrashIsSelectedWithoutRestoringIt() throws {
        let (root, location, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reminder = try notes.create(NoteDraft(title: "예정", reminder: Date().addingTimeInterval(3600)))
        let trashed = try notes.create(NoteDraft(title: "휴지통에 유지"))
        try notes.moveToTrash(trashed.id)
        var routes: [Route] = []
        let model = LibraryModel(theme: try Theme.bundled(), notes: notes, spaces: spaces,
            windows: try WindowStateStore(location: location), preferences: try LibraryPreferencesStore(location: location),
            router: RouteDispatcher { routes.append($0) })
        model.select(.trash)
        let first = try #require(model.index.upcoming.first)
        guard case .note(let upcoming, _) = first else { Issue.record("노트가 필요합니다"); return }
        model.open(upcoming)
        #expect(model.error == nil)
        #expect(routes == [.openNote(reminder.id)])
        #expect(try notes.load(reminder.id) == reminder)
        #expect(try notes.listTrash().notes.map(\.id) == [trashed.id])
        #expect(model.selection == .trash)
    }

    @Test func olderPreferencesKeepIconListsWithoutCorruptRecovery() throws {
        let (root, location, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: location.stateDirectory, withIntermediateDirectories: true)
        let url = location.stateDirectory.appendingPathComponent("library.json")
        let data = Data(#"{"pinnedIcons":[{"emoji":{"_0":"🏠"}}],"recentIcons":[{"image":{"_0":"terminal"}}],"images":["custom.gif"]}"#.utf8)
        try data.write(to: url)
        let preferences = try LibraryPreferencesStore(location: location)
        #expect(preferences.loadWarning == nil)
        #expect(preferences.value.visibleViews == LibraryPreferences().visibleViews)
        #expect(preferences.value.opensLastSelection)
        #expect(preferences.value.lastSelection == .today)
        #expect(preferences.value.pinnedIcons == [.emoji("🏠")])
        #expect(preferences.value.recentIcons == [.image("terminal")])
        #expect(preferences.value.images == ["custom.gif"])
        #expect(try Data(contentsOf: url) == data)
        #expect(try FileManager.default.contentsOfDirectory(atPath: location.stateDirectory.path)
            .allSatisfy { !$0.contains(".corrupt") })
    }
    @Test func viewAndIconPreferencesPersist() throws {
        let (root, location, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let preferences = try LibraryPreferencesStore(location: location)
        let model = LibraryModel(theme: try Theme.bundled(), notes: notes, spaces: spaces,
            windows: try WindowStateStore(location: location), preferences: preferences, router: RouteDispatcher { _ in })
        model.changeSettings { $0.setVisible(.today, false); $0.setVisible(.all, false); $0.opensLastSelection = false; $0.pinnedIcons = [.emoji("🏠")] }
        model.opened()
        #expect(model.selection == .floating)
        let reloaded = try LibraryPreferencesStore(location: location)
        #expect(reloaded.value.pinnedIcons == [.emoji("🏠")])
        #expect(reloaded.value.lastSelection == .floating)
    }
    @Test func imagePathsCannotEscapeStore() throws {
        let root = URL(fileURLWithPath: "/tmp/unused-icons")
        #expect(SpaceIconAssets.url(for: "../notes.md", directory: root) == nil)
        #expect(SpaceIconAssets.url(for: "/etc/passwd", directory: root) == nil)
    }
    @Test func gifImportKeepsAnimationAndShrinksFrames() throws {
        let (root, _, _, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try #require(SpaceIconAssets.url(for: "keyboard", directory: spaces.imageDirectory))
        let name = try SpaceIconAssets.importFile(source, directory: spaces.imageDirectory, maxPixels: 32)
        let image = try #require(NSBitmapImageRep(data: Data(contentsOf: spaces.imageDirectory.appendingPathComponent(name))))
        #expect(image.pixelsWide <= 32 && image.pixelsHigh <= 32)
        #expect((image.value(forProperty: .frameCount) as? Int ?? 0) > 1)
    }
    @Test func oversizedGifRejected() throws {
        let (root, _, _, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.gif")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1_048_577).write(to: url)
        #expect(throws: SpaceIconAssets.ImportError.self) {
            try SpaceIconAssets.importFile(url, directory: spaces.imageDirectory, maxPixels: 64)
        }
    }
    @Test func systemCatalogIncludesFullListsAndKoreanSearchNames() {
        let catalog = IconCatalog()
        #expect(catalog.warning == nil)
        #expect(catalog.symbols.count > 5000)
        #expect(catalog.emoji.count > 1500)
        #expect(catalog.emoji.contains { $0.name.contains("얼굴") })
    }
    @Test func svgAndPngImportsAreRasterizedWithinThePixelLimit() throws {
        let (root, _, _, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("icon.svg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"128\"><rect width=\"256\" height=\"128\" fill=\"red\"/></svg>".utf8).write(to: source)
        let svgName = try SpaceIconAssets.importFile(source, directory: spaces.imageDirectory, maxPixels: 64)
        let rasterURL = spaces.imageDirectory.appendingPathComponent(svgName)
        let raster = try #require(NSBitmapImageRep(data: Data(contentsOf: rasterURL)))
        #expect(max(raster.pixelsWide, raster.pixelsHigh) <= 64)
        let pngName = try SpaceIconAssets.importFile(rasterURL, directory: spaces.imageDirectory, maxPixels: 32)
        let png = try #require(NSBitmapImageRep(data: Data(contentsOf: spaces.imageDirectory.appendingPathComponent(pngName))))
        #expect(max(png.pixelsWide, png.pixelsHigh) <= 32)
    }
    @Test func movingNotesKeepsTitleBodyAndCounts() throws {
        let (root, location, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try spaces.create(name: "A"), b = try spaces.create(name: "B")
        let note = try notes.create(NoteDraft(title: "제목", body: "글", spaceID: a.id))
        let model = LibraryModel(theme: try Theme.bundled(), notes: notes, spaces: spaces,
            windows: try WindowStateStore(location: location), preferences: try LibraryPreferencesStore(location: location), router: RouteDispatcher { _ in })
        try model.move(note.id, to: b.id)
        #expect(model.index.rows(for: .space(a.id)).isEmpty)
        #expect(model.index.rows(for: .space(b.id)).map(\.id) == [note.id])
        #expect(try notes.load(note.id).title == "제목")
        #expect(try notes.load(note.id).body == "글")
        try model.move(note.id, to: nil)
        #expect(model.index.rows(for: .space(nil)).count == 1)
    }
    @Test func deletionWithUnreadableNoteLeavesTheSpace() throws {
        let (root, _, notes, spaces) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let space = try spaces.create(name: "보존")
        try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("broken.md"))
        #expect(throws: StoreError.self) { try spaces.delete(space.id, notes: notes) }
        #expect(spaces.space(for: space.id) != nil)
    }

}
