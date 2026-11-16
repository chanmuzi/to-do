import AppKit

/// Dock 아이콘의 메뉴. 메뉴 막대 메뉴와 같은 항목을 같은 순서로 낸다(종료는 Dock이 따로 넣으므로 뺀다).
/// 메뉴 막대 아이콘을 꺼 두어도 같은 기능을 여기서 쓸 수 있다. 단축키는 적지 않는다(규칙 4).
enum DockMenu {
    /// - Parameter handler: 고른 항목을 받는 곳.
    static func make(areNotesHidden: Bool, handler: @escaping (StatusMenuAction) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.items = entries(areNotesHidden: areNotesHidden).map { entry in
            switch entry {
            case .separator:
                return .separator()
            case .item(let title, _, let action):
                let target = StatusMenuTarget { handler(action) }
                let item = NSMenuItem(title: title, action: #selector(StatusMenuTarget.fire), keyEquivalent: "")
                item.target = target
                // 항목은 target을 붙잡지 않는다. 메뉴가 살아 있는 동안 함께 살도록 여기 맡긴다.
                item.representedObject = target
                return item
            }
        }
        return menu
    }

    /// 메뉴 막대 메뉴에서 종료와 그 앞의 구분선을 뺀 것.
    static func entries(areNotesHidden: Bool) -> [StatusMenuEntry] {
        var entries = StatusMenuModel.entries(areNotesHidden: areNotesHidden).filter {
            if case .item(_, _, .quit) = $0 { false } else { true }
        }
        while entries.last == .separator { entries.removeLast() }
        return entries
    }
}
