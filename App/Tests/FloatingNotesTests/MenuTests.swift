import AppKit
@_spi(Verification) import Editor
@testable import NotePanel
import Models
import Routing
import Testing
import Theme
@testable import FloatingNotes

/// 메뉴 막대 아이콘과 상단 앱 메뉴의 명령, 단축키 표시와 실행을 확인한다(D-340).
/// 한 번에 하나씩 돈다(`.serialized`): 메뉴 항목을 고르는 시험은 메인 액터를 오래 잡는다. 한꺼번에 시작하면
/// 전환 시간을 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct MenuTests {
    private let fixture: AppFixture

    init() throws {
        fixture = try AppFixture()
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
        defer { fixture.cleanUp() }
        let entries = StatusMenuModel.entries(areNotesHidden: false)
        let layout = entries.map { $0.title ?? "-" }
        #expect(layout == [
            "새 노트", "빠른 캡처", "-", "노트 찾기", "라이브러리", "에이전트에게 요청", "-", "노트 모두 숨기기", "-",
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

    @Test func requestMenuIsEnabledAndDispatchesOnce() throws {
        defer { fixture.cleanUp() }
        let menu = NSMenu()
        var chosen: [StatusMenuAction] = []
        StatusMenuBuilder(theme: fixture.theme).fill(
            menu, with: StatusMenuModel.entries(areNotesHidden: false)
        ) { chosen.append($0) }
        let disabled = menu.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title)
        #expect(disabled.isEmpty)
        let library = try #require(menu.items.firstIndex { $0.title == "에이전트에게 요청" })
        menu.performActionForItem(at: library)
        #expect(chosen == [.requestAgent])
        #expect(menu.items.filter { !$0.isSeparatorItem && $0.isEnabled }.map(\.title) == [
            "새 노트", "빠른 캡처", "노트 찾기", "라이브러리", "에이전트에게 요청", "노트 모두 숨기기", "설정", "단축키", "종료",
        ])

        // 같은 요청을 상단 앱 메뉴에서도 고를 수 있다.
        let main = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let items = main.items.compactMap(\.submenu).flatMap(\.items)
        func validity(_ title: String) throws -> Bool {
            fixture.commands.validateMenuItem(try #require(items.first { $0.title == title && !$0.isHidden }))
        }
        for title in ["에이전트에게 요청"] {
            let isValid = try validity(title)
            #expect(isValid, "\(title)")
        }
        for title in ["새 노트", "빠른 캡처", "노트 찾기", "노트 모두 숨기기", "창 닫기", "설정...", "단축키"] {
            let isValid = try validity(title)
            #expect(isValid, "\(title)")
        }
        #expect(try !validity("노트 안에서 찾기"))
        #expect(try !validity("전체 검색"))
    }

    @Test func menuBarIconIsAnEighteenPointTemplateImage() throws {
        defer { fixture.cleanUp() }
        let icon = try MenuBarIcon.load()
        #expect(icon.isTemplate)
        #expect(icon.size.height == 18)
        #expect(icon.size.width < 18 && icon.size.width >= 13)
    }

    @Test func statusMenuActionsGoThroughRouting() {
        defer { fixture.cleanUp() }
        var didQuit = false
        fixture.commands.quit = { didQuit = true }

        for action: StatusMenuAction in [.quickCapture, .findNote, .library, .requestAgent, .settings, .shortcuts] {
            fixture.commands.performStatusMenu(action)
        }
        fixture.commands.performStatusMenu(.quit)

        // 메뉴 막대에서 연 노트 찾기는 노트에 붙지 않는다(spec 4.1).
        #expect(fixture.receivedRoutes == [
            .openCapture, .openBrowse(anchor: nil), .openLibrary, .requestAgent, .openSettings,
            .openShortcuts,
        ])
        #expect(didQuit)
    }

    // MARK: - 앱 메뉴

    @Test func mainMenuDispatchesEachAppShortcutOnce() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)

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

    @Test func viewMenuChangesSharedBodySizeAndPersistsItsLimits() throws {
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let theme = fixture.theme
        SettingsApplication.follow(store, theme: theme, appearanceOverride: nil, setAppearance: { _ in },
            applyDisplay: { _, _ in }, showMenuIcon: { _ in })
        fixture.commands.changeBodySize = { try $0.apply(to: store, theme: theme) }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let view = try #require(menu.item(withTitle: "보기")?.submenu)
        #expect(view.item(withTitle: "본문 확대")?.isHidden == false)
        let minSize = Int(theme.component(.settingsFontMin)), maxSize = Int(theme.component(.settingsFontMax))
        let initial = Int(theme.defaultBodySize)
        #expect(try press(KeyChord(.equals, .command), in: menu))
        #expect(store.settings.bodySize == initial + 1)
        #expect(try press(KeyChord(.equals, [.command, .shift]), in: menu))
        #expect(store.settings.bodySize == initial + 2)
        for _ in minSize...maxSize { _ = try press(KeyChord(.equals, .command), in: menu) }
        #expect(store.settings.bodySize == maxSize)
        for _ in minSize...maxSize { _ = try press(KeyChord(.minus, .command), in: menu) }
        #expect(store.settings.bodySize == minSize)
        #expect(try press(KeyChord(.zero, .command), in: menu))
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.bodySize == initial)
    }

    @Test func everyChordHasExactlyOneItemAndOnlyUnlistedChordsAreHidden() {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let items = menu.items.compactMap(\.submenu).flatMap(\.items).filter { !$0.keyEquivalent.isEmpty }
        #expect(Set(items.map(\.tag)).count == items.count)
        let hidden = items.filter(\.isHidden)
        #expect(hidden.allSatisfy { $0.allowsKeyEquivalentWhenHidden })
        #expect(Set(hidden.map(\.tag)) == Set([KeyChord(.j, .command), KeyChord(.equals, .command)].map(KeyCodeMenu.tag)))
        for entry in ShortcutTable.standard.entries where entry.command != nil {
            for chord in entry.chords {
                let matches = items.filter { $0.tag == KeyCodeMenu.tag(for: chord) }
                #expect(matches.count == 1 && matches.first?.representedObject as? String == entry.command?.rawValue)
            }
        }
    }

    /// 종료, 클립보드 등 실제 동작 대신 어느 항목이 몇 번 호출됐는지만 기록한다.
    @Test func everyVisibleShortcutCallsExactlyItsOwnItemOnce() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let recorder = MenuKeyRecorder()
        let keyed = menu.items.compactMap(\.submenu).flatMap(\.items).filter { !$0.keyEquivalent.isEmpty }
        for item in keyed {
            item.target = recorder
            item.action = #selector(MenuKeyRecorder.record(_:))
        }
        // 아직 화면이 없는 검색 둘은 다음 시험에서 기록 여부를 확인한다.
        let reservedSearches = [AppCommand.findInNote.rawValue, AppCommand.searchAll.rawValue]
        for item in keyed where !item.isHidden && !reservedSearches.contains(item.representedObject as? String ?? "") {
            let key = item.keyEquivalent
            let keyCode = try #require(ShortcutKey.allCases.first { $0.menuKeyEquivalent == (key == "+" ? "=" : key) }).keyCode
            let flags = key == "+" ? item.keyEquivalentModifierMask.union(.shift) : item.keyEquivalentModifierMask
            let character = flags.contains(.shift) ? (key == "9" ? "(" : key.uppercased()) : key
            // charactersIgnoringModifiers에도 Shift가 반영된다. 자모로는 글자 일치 없이 같은 키 자리를 검사한다.
            for input in [character, "ㅏ"] {
                let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil, characters: input, charactersIgnoringModifiers: input,
                    isARepeat: false, keyCode: keyCode))
                recorder.items = []
                #expect(menu.performKeyEquivalent(with: event), "\(item.title)")
                #expect(recorder.items == [item], "\(item.title) \(input)")
            }
        }
    }

    @Test func unavailableSearchesRemainDimAndTheirReservedKeysAreRecordedOnce() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let edit = try #require(menu.item(withTitle: "편집")?.submenu)
        edit.update()
        #expect(edit.item(withTitle: "노트 안에서 찾기")?.isEnabled == false)
        #expect(edit.item(withTitle: "전체 검색")?.isEnabled == false)
        #expect(try press(KeyChord(.f, .command), in: menu))
        #expect(try press(KeyChord(.f, [.shift, .command]), in: menu))
        #expect(fixture.commands.unavailable == [.findInNote, .searchAll])
    }

    /// 키를 바꾼 표로 메뉴를 다시 만들면 새 키를 듣는다.
    @Test func mainMenuFollowsAReboundTable() throws {
        defer { fixture.cleanUp() }
        let table = ShortcutTable.standard.replacing(.settings, with: KeyChord(.k, [.option, .command]))
        let menu = MainMenu.make(appName: "Float", table: table, dispatcher: fixture.commands)

        #expect(try !press(KeyChord(.comma, .command), in: menu))
        #expect(try press(KeyChord(.k, [.option, .command]), in: menu))
        #expect(fixture.receivedRoutes == [.openSettings])
    }

    /// 시스템이 "편집" 메뉴에 끼워 넣는 항목(이모지 및 기호)의 단축키도 그대로 보인다.
    @Test func systemItemsKeepTheirVisibleKeyWhenTheMenuOpens() throws {
        defer { fixture.cleanUp() }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let edit = try #require(menu.items.compactMap(\.submenu).first { $0.title == "편집" })
        let added = NSMenuItem(title: "이모지 및 기호", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "e")
        added.keyEquivalentModifierMask = [.function]
        edit.addItem(added)

        edit.update()
        #expect(edit.items.filter { $0.title == "이모지 및 기호" }.count == 1)
        #expect(!added.isHidden && added.keyEquivalent == "e" && added.keyEquivalentModifierMask == [.function])
    }

    /// 한글 입력 소스에서 이벤트에 라틴 글자가 아닌 글자(두벌식의 자모)가 실려 와도 표에 적힌 자리의 키가 듣는다.
    /// AppKit이 글자로 맞는 항목을 찾지 못하면 앱 메뉴가 키 자리로 한 번 더 찾는다(`KeyCodeMenu`).
    @Test func mainMenuHearsShortcutsByKeyPositionUnderAKoreanInputSource() throws {
        defer { fixture.cleanUp() }
        var forwardedUndo = 0
        fixture.commands.forwardUndo = { _ in forwardedUndo += 1 }
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
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
        let keyWindow = try #require(fixture.notePanels.openNoteIDs.first.flatMap(fixture.notePanels.window(for:)))
        fixture.notePanels.isKeyPanel = { $0 === keyWindow }
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

    @Test func formatAndNoteCommandsFollowKeyWindowSelectionAndPin() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "검증", body: "한글\n```\n코드\n```"))
        let window = try #require(fixture.notePanels.window(for: id))
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let format = try #require(menu.item(withTitle: "서식")?.submenu)
        let note = try #require(menu.item(withTitle: "노트")?.submenu)
        func enabled(in menu: NSMenu) -> [String] {
            menu.update()
            return menu.items.filter { !$0.isSeparatorItem && !$0.isHidden && $0.isEnabled }.map(\.title)
        }
        adapter.focus()
        #expect(enabled(in: format).isEmpty && enabled(in: note).isEmpty)
        fixture.notePanels.isKeyPanel = { $0 === window }
        adapter.editor.forcesActiveAppearance = true
        adapter.editor.selectedRange = NSRange(location: 0, length: 2)
        #expect(enabled(in: format).contains("취소선"))
        #expect(enabled(in: note) == ["제목 고치기", "항상 위에 고정 해제", "리마인더 설정", "스페이스 옮기기", "더 보기 메뉴"])
        note.performActionForItem(at: note.indexOfItem(withTitle: "항상 위에 고정 해제"))
        #expect(enabled(in: note).contains("항상 위에 고정"))
        format.performActionForItem(at: format.indexOfItem(withTitle: "취소선"))
        #expect(adapter.text.hasPrefix("~~한글~~"))
        // 같은 자리의 한글 이벤트를 메뉴 객체에만 전달한다. 한 번 벗겨진 원문으로 중복 실행도 확인한다.
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil, characters: "ㅌ", charactersIgnoringModifiers: "ㅌ",
            isARepeat: false, keyCode: ShortcutKey.x.keyCode))
        #expect(menu.performKeyEquivalent(with: event))
        #expect(adapter.text == "한글\n```\n코드\n```")
        adapter.editor.selectedRange = (adapter.text as NSString).range(of: "코드")
        #expect(enabled(in: format) == ["코드 블록"])
        window.makeFirstResponder(nil)
        #expect(enabled(in: format).isEmpty && enabled(in: note).count == 5)
    }
}

@MainActor private final class MenuKeyRecorder: NSObject {
    var items: [NSMenuItem] = []
    @objc func record(_ item: NSMenuItem) { items.append(item) }
}

extension MenuTests {
    @Test func commandReturnMenuRoutesToActiveToggle() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "검증", body: "+ 제목\n\t자식"))
        let window = try #require(fixture.notePanels.window(for: id))
        fixture.notePanels.isKeyPanel = { $0 === window }
        adapter.focus()
        adapter.editor.forcesActiveAppearance = true
        adapter.editor.selectedRange = NSRange(location: 3, length: 0)
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let item = try #require(menu.item(withTitle: "서식")?.submenu?.item(withTitle: "완료 표시, 접기와 펼치기"))
        #expect(fixture.commands.validateMenuItem(item))
        #expect(try press(KeyChord(.returnKey, .command), in: menu))
        #expect(adapter.editor.foldedLines == [0])
        #expect(try press(KeyChord(.returnKey, .command), in: menu))
        #expect(adapter.editor.foldedLines.isEmpty)
    }
}
