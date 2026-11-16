import AppKit

/// 앱 메뉴. 지금은 종료만 있다. 메뉴 막대 아이콘과 나머지 항목은 4단계에서 만든다.
enum MainMenu {
    static func make(appName: String) -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "\(appName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
