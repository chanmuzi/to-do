import AppKit

/// 앱 메뉴. 글을 쓰는 데 필요한 것(편집 메뉴, 새 노트, 창 닫기)만 있다.
/// 메뉴 막대 아이콘과 나머지 항목, 단축키 표는 4단계에서 만든다.
enum MainMenu {
    /// - Parameter target: `newNote(_:)`, `closeNoteWindow(_:)`를 받는 쪽.
    static func make(appName: String, target: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: appName, items: [
            item("\(appName) 종료", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        menu.addItem(submenu(title: "파일", items: [
            item("새 노트", #selector(AppDelegate.newNote(_:)), "n", target: target),
            item("창 닫기", #selector(AppDelegate.closeNoteWindow(_:)), "w", target: target),
        ]))
        menu.addItem(submenu(title: "편집", items: [
            item("실행 취소", Selector(("undo:")), "z"),
            item("다시 실행", Selector(("redo:")), "Z"),
            .separator(),
            item("오려두기", #selector(NSText.cut(_:)), "x"),
            item("복사", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("모두 선택", #selector(NSText.selectAll(_:)), "a"),
        ]))
        return menu
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        submenu.items = items
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }

    private static func item(
        _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
