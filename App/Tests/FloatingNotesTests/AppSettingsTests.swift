import AppKit
import Foundation
import Models
import Routing
import Testing
@testable import FloatingNotes

/// 메뉴 막대 아이콘을 보일지의 설정과, 아이콘 없이도 같은 기능에 닿는 길(Dock 메뉴, 앱 메뉴).
@Suite struct AppSettingsTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("app-settings-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func menuBarIconIsShownByDefaultAndTheChoicePersists() throws {
        defer { cleanUp() }
        let store = try AppSettingsStore(stateDirectory: directory)
        #expect(store.settings.showsMenuBarIcon)
        #expect(store.loadWarning == nil)
        // 바꾼 것이 없으면 파일을 만들지 않는다.
        try store.update { $0.showsMenuBarIcon = true }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("app-settings.json").path))

        try store.update { $0.showsMenuBarIcon = false }

        let reloaded = try AppSettingsStore(stateDirectory: directory)
        #expect(!reloaded.settings.showsMenuBarIcon)
        try reloaded.update { $0.showsMenuBarIcon = true }
        #expect(try AppSettingsStore(stateDirectory: directory).settings.showsMenuBarIcon)
    }

    @Test func olderOrBrokenSettingsFilesFallBackToDefaultsWithoutLosingTheFile() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("app-settings.json")
        // 항목이 없는 예전 파일.
        try Data("{}".utf8).write(to: file)
        let older = try AppSettingsStore(stateDirectory: directory)
        #expect(older.settings == AppSettings())
        #expect(older.loadWarning == nil)
        // 깨진 파일은 옆으로 옮기고 알린다.
        try Data("{ 깨진 파일".utf8).write(to: file)
        let broken = try AppSettingsStore(stateDirectory: directory)
        #expect(broken.settings == AppSettings())
        #expect(broken.loadWarning?.contains("app-settings.json.corrupt") == true)
        #expect(FileManager.default.fileExists(atPath: file.path + ".corrupt"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func launchArgumentOverridesTheStoredChoiceForOneRun() throws {
        #expect(try LaunchOptions(arguments: ["app"]).menuBarIconOverride == nil)
        #expect(try LaunchOptions(arguments: ["app", "--menu-bar-icon", "off"]).menuBarIconOverride == false)
        #expect(try LaunchOptions(arguments: ["app", "--menu-bar-icon", "on"]).menuBarIconOverride == true)
        #expect(throws: LaunchOptions.ParseError.invalidSwitch(flag: "--menu-bar-icon", value: "maybe")) {
            try LaunchOptions(arguments: ["app", "--menu-bar-icon", "maybe"])
        }
        #expect(throws: LaunchOptions.ParseError.missingValue("--menu-bar-icon")) {
            try LaunchOptions(arguments: ["app", "--menu-bar-icon"])
        }
    }

    // MARK: - 아이콘 없이 닿는 길

    @Test func dockMenuHasTheStatusMenuEntriesWithoutQuit() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        var chosen: [StatusMenuAction] = []
        let menu = DockMenu.make(areNotesHidden: false) { chosen.append($0) }

        #expect(menu.items.map { $0.isSeparatorItem ? "-" : $0.title } == [
            "새 노트", "빠른 캡처", "-", "노트 찾기", "라이브러리", "AI 패널", "-", "노트 모두 숨기기", "-",
            "설정", "단축키",
        ])
        #expect(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
        #expect(DockMenu.make(areNotesHidden: true) { _ in }.items[7].title == "노트 모두 보이기")
        for index in menu.items.indices where !menu.items[index].isSeparatorItem {
            menu.performActionForItem(at: index)
        }
        #expect(chosen == [
            .newNote, .quickCapture, .findNote, .library, .aiPanel, .toggleNotesHidden, .settings, .shortcuts,
        ])
    }

    /// 메뉴 막대 메뉴의 모든 항목이 앱 메뉴에도 보이는 항목으로 있고, 골랐을 때 같은 일을 한다.
    @Test func mainMenuOffersEveryStatusMenuEntry() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)
        func visible(in menu: NSMenu) -> [(menu: NSMenu, index: Int, title: String)] {
            menu.items.enumerated().flatMap { index, item -> [(menu: NSMenu, index: Int, title: String)] in
                if let submenu = item.submenu { return visible(in: submenu) }
                return item.isHidden || item.isSeparatorItem ? [] : [(menu, index, item.title)]
            }
        }
        let items = visible(in: menu)
        let titles = items.map(\.title)
        for title in StatusMenuModel.entries(areNotesHidden: false).compactMap(\.title) where title != "종료" {
            #expect(titles.contains(title), "\(title)")
        }
        #expect(titles.contains("플로팅 노트 종료"))

        for title in ["빠른 캡처", "노트 찾기", "라이브러리", "AI 패널", "설정", "단축키", "새 노트", "노트 모두 숨기기"] {
            let item = try #require(items.first { $0.title == title })
            item.menu.performActionForItem(at: item.index)
        }

        #expect(fixture.receivedRoutes == [
            .openCapture, .openBrowse(anchor: nil), .openLibrary, .openAIPanel(context: nil), .openSettings,
            .openShortcuts, .newNote(NewNoteRequest()), .toggleAllNotesHidden,
        ])
        #expect(fixture.notePanels.openNoteIDs.count == 1)
        #expect(fixture.notePanels.areNotesHidden)
        // 숨긴 중이면 앱 메뉴의 그 항목은 "노트 모두 보이기"가 된다.
        let toggle = try #require(items.first { $0.title == "노트 모두 숨기기" })
        #expect(fixture.commands.validateMenuItem(toggle.menu.items[toggle.index]))
        #expect(toggle.menu.items[toggle.index].title == "노트 모두 보이기")
        toggle.menu.performActionForItem(at: toggle.index)
        #expect(fixture.commands.validateMenuItem(toggle.menu.items[toggle.index]))
        #expect(toggle.menu.items[toggle.index].title == "노트 모두 숨기기")
        #expect(!fixture.notePanels.areNotesHidden)
    }
}
