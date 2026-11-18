import AppKit

/// 앱 메뉴. 보이는 항목에는 단축키를 적지 않는다(규칙 4).
///
/// 단축키는 보이지 않는 짝 항목이 받는다: 같은 동작에 `keyEquivalent`를 넣고 숨긴 뒤
/// `allowsKeyEquivalentWhenHidden`을 켠 항목이다. 메뉴에는 나타나지 않고 키만 듣는다.
/// 노트 창의 단축키(spec 13 "노트 창")는 `ShortcutTable`에서 읽어 모두 이렇게 넣는다. 편집기의 단축키는
/// 편집기가 먼저 받고(뷰가 메뉴보다 앞선다), 표에 없는 표준 편집 키(⌘Z, ⌘C 등)는 여기에 적혀 있다.
///
/// 키를 견주는 방식: AppKit은 메뉴 항목의 `keyEquivalent`를 이벤트의 글자와 견준다. 그것으로 맞는 항목이
/// 없으면 `KeyCodeMenu`가 키 자리(가상 키 코드)와 보조 키로 숨긴 짝 항목을 한 번 더 찾는다. 그래서 이벤트에
/// 라틴 글자가 아닌 글자(한글 자모 등)가 실려 와도 표에 적힌 자리의 키가 듣는다(`ShortcutKey`).
enum MainMenu {
    /// - Parameter dispatcher: 노트 창 동작과 실행 취소를 받는 쪽.
    static func make(appName: String, table: ShortcutTable, dispatcher: AppCommandDispatcher) -> NSMenu {
        func command(_ title: String, _ command: AppCommand) -> [NSMenuItem] {
            let visible = NSMenuItem(
                title: title, action: #selector(AppCommandDispatcher.performMenuCommand(_:)), keyEquivalent: ""
            )
            visible.target = dispatcher
            visible.representedObject = command.rawValue
            return [visible] + hiddenItems(for: [command], in: table, dispatcher: dispatcher)
        }
        let listed: Set<AppCommand> = [.newNote, .findNote, .closeWindow, .settings, .shortcuts, .nextNote]
        let unlisted = table.entries(in: .noteWindow).compactMap(\.command).filter { !listed.contains($0) }
        let undo = #selector(AppCommandDispatcher.undoOrRestoreTrash(_:))

        // 노트를 누르면 앱이 앞으로 오고 메뉴 막대에 이 메뉴가 보인다(D-025). 차례는 시안 화면 1의 메뉴 막대다.
        let menu = KeyCodeMenu(title: "")
        // 메뉴 막대 메뉴의 항목은 여기에도 모두 있다. 메뉴 막대 아이콘을 꺼 두어도 같은 기능을 쓸 수 있다.
        menu.addItem(submenu(
            title: appName,
            items: [plain("\(appName)에 관하여", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))]
                + [.separator()] + command("설정...", .settings) + [.separator()]
                + standard("\(appName) 종료", #selector(NSApplication.terminate(_:)), KeyChord(.q, .command))
        ))
        menu.addItem(submenu(
            title: "파일",
            items: command("새 노트", .newNote) + command("빠른 캡처", .quickCapture) + [.separator()]
                + command("노트 찾기", .findNote) + command("라이브러리", .library) + command("AI 패널", .aiPanel)
                + [.separator()] + command("창 닫기", .closeWindow)
                + hiddenItems(for: unlisted, in: table, dispatcher: dispatcher)
        ))
        menu.addItem(submenu(
            title: "편집",
            items: standard("실행 취소", undo, KeyChord(.z, .command), target: dispatcher)
                + standard("다시 실행", Selector(("redo:")), KeyChord(.z, [.shift, .command]))
                + [.separator()]
                + standard("오려두기", #selector(NSText.cut(_:)), KeyChord(.x, .command))
                + standard("복사", #selector(NSText.copy(_:)), KeyChord(.c, .command))
                + standard("붙여넣기", #selector(NSText.paste(_:)), KeyChord(.v, .command))
                + standard("모두 선택", #selector(NSText.selectAll(_:)), KeyChord(.a, .command))
        ))
        menu.addItem(submenu(title: "보기", items: command(StatusMenuModel.hideAllTitle, .toggleNotesHidden)))
        menu.addItem(submenu(title: "창", items: command("다음 노트로", .nextNote)))
        menu.addItem(submenu(title: "도움말", items: command("단축키", .shortcuts)))
        return menu
    }

    /// 표에 있는 동작마다 키만 듣는 숨은 항목을 만든다. 키가 없는 동작은 건너뛴다.
    private static func hiddenItems(
        for commands: [AppCommand], in table: ShortcutTable, dispatcher: AppCommandDispatcher
    ) -> [NSMenuItem] {
        commands.compactMap { command in
            // "어디서나" 줄의 키는 전역 단축키가 받는다. 메뉴에는 노트 창의 키만 넣는다.
            guard let entry = table.entry(for: command), entry.group == .noteWindow,
                  let chord = entry.chords.first
            else { return nil }
            let item = keyOnlyItem(
                entry.action, #selector(AppCommandDispatcher.performMenuCommand(_:)), chord, target: dispatcher
            )
            item.representedObject = command.rawValue
            return item
        }
    }

    /// 보이는 항목(단축키 없음)과 키만 듣는 숨은 짝.
    private static func standard(
        _ title: String, _ action: Selector, _ chord: KeyChord, target: AnyObject? = nil
    ) -> [NSMenuItem] {
        let visible = NSMenuItem(title: title, action: action, keyEquivalent: "")
        visible.target = target
        return [visible, keyOnlyItem(title, action, chord, target: target)]
    }

    /// 단축키가 없는 보이는 항목.
    private static func plain(_ title: String, _ action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    private static func keyOnlyItem(
        _ title: String, _ action: Selector, _ chord: KeyChord, target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: chord.key.menuKeyEquivalent)
        item.keyEquivalentModifierMask = chord.modifiers.eventFlags
        item.tag = KeyCodeMenu.tag(for: chord)
        item.target = target
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        submenu.items = items
        // 시스템이 나중에 끼워 넣는 항목의 단축키도 보이지 않게 한다.
        submenu.delegate = MenuShortcutConcealer.shared
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }
}
