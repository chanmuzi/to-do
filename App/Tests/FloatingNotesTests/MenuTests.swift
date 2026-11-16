import AppKit
import Models
import Routing
import Testing
import Theme
@testable import FloatingNotes

/// 메뉴 막대 메뉴(spec 4.3)와 앱 메뉴: 단축키를 보이지 않으면서(규칙 4) 키는 듣는지.
/// 한 번에 하나씩 돈다(`.serialized`): 메뉴 항목을 고르는 시험은 메인 액터를 오래 잡는다. 한꺼번에 시작하면
/// 전환 시간을 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct MenuTests {
    private let fixture: AppFixture

    init() throws {
        fixture = try AppFixture()
    }

    private func visibleItems(of menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            (item.isHidden ? [] : [item]) + (item.submenu.map(visibleItems(of:)) ?? [])
        }
    }

    private func press(_ chord: KeyChord, in menu: NSMenu) throws -> Bool {
        let characters = chord.key.menuKeyEquivalent
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: chord.modifiers.eventFlags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: chord.modifiers.contains(.shift) ? characters.uppercased() : characters,
            isARepeat: false, keyCode: chord.key.keyCode
        ))
        return menu.performKeyEquivalent(with: event)
    }

    // MARK: - 메뉴 막대

    @Test func statusMenuHasTheSpecifiedOrderIconsAndSeparators() {
        let entries = StatusMenuModel.entries(areNotesHidden: false)
        let layout = entries.map { $0.title ?? "-" }
        #expect(layout == [
            "새 노트", "빠른 캡처", "-", "노트 찾기", "라이브러리", "AI 패널", "-", "노트 모두 숨기기", "-",
            "설정", "단축키", "-", "종료",
        ])
        // 종료를 뺀 항목에는 아이콘이 있다.
        for entry in entries {
            guard case .item(let title, let symbol, _) = entry else { continue }
            #expect((symbol == nil) == (title == "종료"), "\(title)")
            if let symbol { #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)") }
        }
    }

    @Test func hideAllTitleFlipsWithTheHiddenState() throws {
        defer { fixture.cleanUp() }
        _ = try fixture.open(NoteDraft(title: "숨길 노트"))
        func toggleTitle() -> String? {
            StatusMenuModel.entries(areNotesHidden: fixture.notePanels.areNotesHidden).first {
                if case .item(_, _, .toggleNotesHidden) = $0 { true } else { false }
            }?.title
        }

        #expect(toggleTitle() == "노트 모두 숨기기")
        fixture.commands.performStatusMenu(.toggleNotesHidden)
        #expect(fixture.notePanels.areNotesHidden)
        #expect(toggleTitle() == "노트 모두 보이기")
        fixture.commands.performStatusMenu(.toggleNotesHidden)
        #expect(toggleTitle() == "노트 모두 숨기기")
    }

    @Test func builtStatusMenuShowsNoKeyEquivalentsAndReportsTheChosenAction() {
        defer { fixture.cleanUp() }
        let menu = NSMenu()
        var chosen: [StatusMenuAction] = []
        StatusMenuBuilder(theme: fixture.theme).fill(
            menu, with: StatusMenuModel.entries(areNotesHidden: true)
        ) { chosen.append($0) }

        #expect(menu.items.count == 13)
        #expect(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
        #expect(menu.items.filter(\.isSeparatorItem).count == 4)
        #expect(menu.items[7].title == "노트 모두 보이기")
        #expect(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.view is MenuBarRowView })
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 12)
        #expect(chosen == [.newNote, .quit])
    }

    /// 여는 화면이 아직 이어지지 않은 항목은 메뉴에 자리와 이름 그대로 있되(spec 4.3) 고를 수 없다:
    /// 눌러도 아무 일이 없는 항목을 내놓지 않는다(D-034). 메뉴 막대 메뉴, 앱 메뉴 모두 같다.
    @Test func entriesForUnconnectedScreensAreDisabledNotRemoved() throws {
        defer { fixture.cleanUp() }
        let unconnected: Set<StatusMenuAction> = [.library, .aiPanel, .settings, .shortcuts]
        let connected: [StatusMenuAction] = [.newNote, .quickCapture, .findNote, .toggleNotesHidden, .quit]
        #expect(connected.filter(\.isConnected) == connected)
        #expect(unconnected.filter(\.isConnected).isEmpty)

        let menu = NSMenu()
        var chosen: [StatusMenuAction] = []
        StatusMenuBuilder(theme: fixture.theme).fill(
            menu, with: StatusMenuModel.entries(areNotesHidden: false)
        ) { chosen.append($0) }
        let disabled = menu.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title)
        #expect(disabled == ["라이브러리", "AI 패널", "설정", "단축키"])
        // 고를 수 없는 항목은 눌러도 동작이 가지 않는다(고를 수 있는 항목은 위의 시험이 본다).
        let library = try #require(menu.items.firstIndex { $0.title == "라이브러리" })
        menu.performActionForItem(at: library)
        #expect(chosen.isEmpty)
        #expect(menu.items.filter { !$0.isSeparatorItem && $0.isEnabled }.map(\.title) == [
            "새 노트", "빠른 캡처", "노트 찾기", "노트 모두 숨기기", "종료",
        ])

        // 앱 메뉴: 보이는 항목은 열릴 때 고를 수 없게 되고, 키만 듣는 숨은 짝은 그대로 듣는다.
        let main = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)
        let items = main.items.compactMap(\.submenu).flatMap(\.items)
        func validity(_ title: String) throws -> Bool {
            fixture.commands.validateMenuItem(try #require(items.first { $0.title == title && !$0.isHidden }))
        }
        for title in ["라이브러리", "AI 패널", "설정", "단축키"] {
            let isValid = try validity(title)
            #expect(!isValid, "\(title)")
        }
        for title in ["새 노트", "빠른 캡처", "노트 찾기", "노트 모두 숨기기", "창 닫기"] {
            let isValid = try validity(title)
            #expect(isValid, "\(title)")
        }
        let hidden = items.filter(\.isHidden)
        #expect(hidden.filter { fixture.commands.validateMenuItem($0) }.count == hidden.count)
    }

    @Test func menuBarIconIsAnEighteenPointTemplateImage() throws {
        defer { fixture.cleanUp() }
        let icon = try MenuBarIcon.load()
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 18, height: 18))
    }

    @Test func statusMenuActionsGoThroughRouting() {
        defer { fixture.cleanUp() }
        var didQuit = false
        fixture.commands.quit = { didQuit = true }

        for action: StatusMenuAction in [.quickCapture, .findNote, .library, .aiPanel, .settings, .shortcuts] {
            fixture.commands.performStatusMenu(action)
        }
        fixture.commands.performStatusMenu(.quit)

        // 메뉴 막대에서 연 노트 찾기는 노트에 붙지 않는다(spec 4.1).
        #expect(fixture.receivedRoutes == [
            .openCapture, .openBrowse(anchor: nil), .openLibrary, .openAIPanel(context: nil), .openSettings,
            .openShortcuts,
        ])
        #expect(didQuit)
    }

    // MARK: - 앱 메뉴

    @Test func mainMenuShowsNoKeyEquivalentsButStillHearsThem() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)

        let visible = visibleItems(of: menu)
        #expect(visible.allSatisfy { $0.keyEquivalent.isEmpty })
        #expect(visible.map(\.title).contains("새 노트"))
        #expect(visible.map(\.title).contains("실행 취소"))

        #expect(try press(KeyChord(.comma, .command), in: menu))
        #expect(try press(KeyChord(.slash, .command), in: menu))
        #expect(try press(KeyChord(.p, .command), in: menu))
        #expect(try press(KeyChord(.n, .command), in: menu))
        #expect(fixture.receivedRoutes == [
            .openSettings, .openShortcuts, .openBrowse(anchor: nil), .newNote(NewNoteRequest()),
        ])
        #expect(fixture.notePanels.openNoteIDs.count == 1)
        // 표에 없는 키는 듣지 않는다.
        #expect(try !press(KeyChord(.k, [.control, .option, .command]), in: menu))
    }

    @Test func everyNoteWindowRowHasAHiddenKeyItem() {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)
        func hidden(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { ($0.isHidden ? [$0] : []) + ($0.submenu.map(hidden(in:)) ?? []) }
        }
        let keyOnly = hidden(in: menu)

        #expect(keyOnly.allSatisfy { $0.allowsKeyEquivalentWhenHidden && !$0.keyEquivalent.isEmpty })
        let commands = Set(keyOnly.compactMap { $0.representedObject as? String }.compactMap(AppCommand.init(rawValue:)))
        #expect(commands == Set(ShortcutTable.standard.entries(in: .noteWindow).compactMap(\.command)))
        for entry in ShortcutTable.standard.entries(in: .noteWindow) {
            let chord = entry.chords[0]
            let item = keyOnly.first { $0.representedObject as? String == entry.command?.rawValue }
            #expect(item?.keyEquivalent == chord.key.menuKeyEquivalent, "\(entry.action)")
            #expect(item?.keyEquivalentModifierMask == chord.modifiers.eventFlags, "\(entry.action)")
        }
    }

    /// 키를 바꾼 표로 메뉴를 다시 만들면 새 키를 듣는다.
    @Test func mainMenuFollowsAReboundTable() throws {
        defer { fixture.cleanUp() }
        let table = ShortcutTable.standard.replacing(.settings, with: KeyChord(.k, [.option, .command]))
        let menu = MainMenu.make(appName: "플로팅 노트", table: table, dispatcher: fixture.commands)

        #expect(try !press(KeyChord(.comma, .command), in: menu))
        #expect(try press(KeyChord(.k, [.option, .command]), in: menu))
        #expect(fixture.receivedRoutes == [.openSettings])
    }

    /// 시스템이 "편집" 메뉴에 끼워 넣는 항목(이모지 및 기호)의 단축키도 보이지 않게 한다.
    @Test func keyEquivalentsOfItemsAddedLaterAreConcealedWhenTheMenuOpens() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)
        let edit = try #require(menu.items.compactMap(\.submenu).first { $0.title == "편집" })
        let added = NSMenuItem(title: "이모지 및 기호", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "e")
        added.keyEquivalentModifierMask = [.function]
        edit.addItem(added)

        edit.delegate?.menuNeedsUpdate?(edit)
        edit.delegate?.menuNeedsUpdate?(edit)

        #expect(visibleItems(of: menu).allSatisfy { $0.keyEquivalent.isEmpty })
        #expect(edit.items.filter { $0.title == "이모지 및 기호" }.count == 2)
        #expect(added.isHidden && added.allowsKeyEquivalentWhenHidden && added.keyEquivalent == "e")
    }

    /// 한글 입력 소스에서 이벤트에 라틴 글자가 아닌 글자(두벌식의 자모)가 실려 와도 표에 적힌 자리의 키가 듣는다.
    /// AppKit이 글자로 맞는 항목을 찾지 못하면 앱 메뉴가 키 자리로 한 번 더 찾는다(`KeyCodeMenu`).
    @Test func mainMenuHearsShortcutsByKeyPositionUnderAKoreanInputSource() throws {
        defer { fixture.cleanUp() }
        var forwardedUndo = 0
        fixture.commands.forwardUndo = { _ in forwardedUndo += 1 }
        let menu = MainMenu.make(appName: "플로팅 노트", table: .standard, dispatcher: fixture.commands)
        func press(_ chord: KeyChord, characters: String) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: chord.modifiers.eventFlags, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: chord.key.keyCode
            ))
            return menu.performKeyEquivalent(with: event)
        }

        // 두벌식에서 N 자리는 "ㅜ", P 자리는 "ㅔ", Z 자리는 "ㅋ"다.
        #expect(try press(KeyChord(.n, .command), characters: "ㅜ"))
        #expect(try press(KeyChord(.p, .command), characters: "ㅔ"))
        #expect(try press(KeyChord(.t, [.shift, .command]), characters: "ㅆ"))
        #expect(try press(KeyChord(.z, .command), characters: "ㅋ"))
        #expect(fixture.receivedRoutes == [.newNote(NewNoteRequest()), .openBrowse(anchor: nil)])
        #expect(forwardedUndo == 1)
        // 보조 키가 다르면 듣지 않는다. 표에 없는 자리도 듣지 않는다.
        #expect(try !press(KeyChord(.n, [.option, .command]), characters: "ㅜ"))
        #expect(try !press(KeyChord(.k, [.control, .command]), characters: "ㅏ"))
        // 라틴 글자로 오는 보통의 경우는 한 번만 한다(글자로 맞은 뒤 자리로 또 하지 않는다).
        #expect(try press(KeyChord(.comma, .command), characters: ","))
        #expect(fixture.receivedRoutes.count == 3)
    }
}
