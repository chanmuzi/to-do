import AppKit
import Editor

/// 상단 앱 메뉴의 보이는 명령이 직접 키를 듣는다(규칙 4, D-340).
enum MainMenu {
    static func make(appName: String, table: ShortcutTable, dispatcher: AppCommandDispatcher) -> NSMenu {
        let menu = KeyCodeMenu(title: "")
        func add(_ title: String, _ items: [NSMenuItem]) {
            let submenu = NSMenu(title: title)
            submenu.items = items
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        }

        func command(_ title: String, _ command: AppCommand, chord: KeyChord? = nil) -> NSMenuItem {
            let item = keyed(title, #selector(AppCommandDispatcher.performMenuCommand(_:)), chord ?? table.chord(for: command))
            item.target = dispatcher
            item.representedObject = command.rawValue
            if (command == .findInNote || command == .searchAll), !command.isConnected, !item.keyEquivalent.isEmpty {
                menu.reservedKeys[item.tag] = { dispatcher.perform(command) }
            }
            return item
        }

        func format(_ title: String, _ action: EditorAction) -> NSMenuItem {
            guard let binding = EditorShortcuts.binding(for: action),
                  let key = ShortcutKey.allCases.first(where: { $0.keyCode == binding.keyCode }) else {
                preconditionFailure("서식 메뉴에 연결할 편집 단축키가 없습니다: \(action)")
            }
            let chord = KeyChord(key, ShortcutModifiers(eventFlags: binding.flags))
            let item = keyed(title, #selector(AppCommandDispatcher.performFormat(_:)), chord)
            item.target = dispatcher
            item.representedObject = action
            return item
        }

        add(appName, [
            keyed("\(appName)에 관하여", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), nil), .separator(),
            command("설정...", .settings), .separator(),
            keyed("\(appName) 종료", #selector(NSApplication.terminate(_:)), KeyChord(.q, .command)),
        ])
        add("파일", [
            command("새 노트", .newNote), command("빠른 캡처", .quickCapture), .separator(),
            command("노트 찾기", .findNote), command("라이브러리", .library), command("에이전트에게 요청", .requestAgent),
            .separator(), command("창 닫기", .closeWindow),
        ])
        let undo = keyed("실행 취소", #selector(AppCommandDispatcher.undoOrRestoreTrash(_:)), KeyChord(.z, .command))
        undo.target = dispatcher
        add("편집", [
            undo, keyed("다시 실행", Selector(("redo:")), KeyChord(.z, [.shift, .command])), .separator(),
            keyed("오려두기", #selector(NSText.cut(_:)), KeyChord(.x, .command)),
            keyed("복사", #selector(NSText.copy(_:)), KeyChord(.c, .command)),
            keyed("붙여넣기", #selector(NSText.paste(_:)), KeyChord(.v, .command)),
            keyed("안에 붙여넣기", MarkdownEditor.pasteInsideAction, KeyChord(.v, [.option, .command])),
            keyed("블록 복제", MarkdownEditor.duplicateBlockAction, KeyChord(.d, .command)),
            keyed("구분선 넣기", MarkdownEditor.insertDividerAction, nil),
            keyed("모두 선택", #selector(NSText.selectAll(_:)), KeyChord(.a, .command)), .separator(),
            command("노트 안에서 찾기", .findInNote), command("전체 검색", .searchAll),
        ])
        add("서식", [
            format("굵게", .bold), format("취소선", .strikethrough), format("밑줄", .underline),
            format("인라인 코드", .inlineCode), format("마지막 색 걸기", .highlight), format("링크 추가", .link),
            .separator(), format("제목 1", .heading(1)), format("제목 2", .heading(2)), format("제목 3", .heading(3)),
            format("투두로 바꾸기", .toggleTodo), format("코드 블록", .codeBlock), .separator(),
            format("완료 표시, 접기와 펼치기", .toggleDone), format("줄 위로 옮기기", .moveLineUp), format("줄 아래로 옮기기", .moveLineDown),
            format("고른 블록 위로 옮기기", .moveSelectedBlockUp), format("고른 블록 아래로 옮기기", .moveSelectedBlockDown),
        ])
        add("노트", [
            command("제목 고치기", .editTitle), command("항상 위에 고정", .togglePin),
            command("리마인더 설정", .setReminder), command("스페이스 옮기기", .moveToSpace), .separator(),
            command("더 보기 메뉴", .moreMenu),
        ] + (table.entry(for: .openAgentWindow)?.chords ?? []).map {
            hidden(command("노트에서 에이전트 창 열기", .openAgentWindow, chord: $0))
        })
        add("보기", [
            command(StatusMenuModel.hideAllTitle, .toggleNotesHidden), .separator(),
            command("본문 확대", .enlargeBody), command("본문 축소", .reduceBody), command("본문 기본 크기", .resetBodySize),
        ] + (table.entry(for: .enlargeBody)?.chords.dropFirst() ?? []).map {
            hidden(command("본문 확대", .enlargeBody, chord: $0))
        })
        add("창", [command("다음 노트로", .nextNote)])
        add("도움말", [command("단축키", .shortcuts)])
        return menu
    }

    private static func keyed(_ title: String, _ action: Selector, _ chord: KeyChord?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let chord {
            let plus = chord.key == .equals && chord.modifiers.contains(.shift)
            item.keyEquivalent = plus ? "+" : chord.key.menuKeyEquivalent
            item.keyEquivalentModifierMask = (plus ? chord.modifiers.subtracting(.shift) : chord.modifiers).eventFlags
            item.tag = KeyCodeMenu.tag(for: chord)
        }
        return item
    }

    private static func hidden(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }
}
