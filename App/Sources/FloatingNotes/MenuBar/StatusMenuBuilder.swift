import AppKit
import Theme

/// `StatusMenuModel`의 내용을 `NSMenu`로 만든다. 항목에 `keyEquivalent`를 넣지 않는다(spec 19, 규칙 4).
struct StatusMenuBuilder {
    let theme: Theme

    /// - Parameter handler: 고른 항목을 받는 곳.
    func fill(_ menu: NSMenu, with entries: [StatusMenuEntry], handler: @escaping (StatusMenuAction) -> Void) {
        menu.autoenablesItems = false
        menu.minimumWidth = theme.component(.menuWidth)
        menu.items = entries.map { entry in
            switch entry {
            case .separator:
                return .separator()
            case .item(let title, let symbol, let action):
                let target = StatusMenuTarget { handler(action) }
                let item = NSMenuItem(title: title, action: #selector(StatusMenuTarget.fire), keyEquivalent: "")
                item.target = target
                // 항목은 target을 붙잡지 않는다. 메뉴가 살아 있는 동안 함께 살도록 여기 맡긴다.
                item.representedObject = target
                item.view = MenuBarRowView(theme: theme, title: title, symbolName: symbol)
                return item
            }
        }
    }
}

/// 메뉴 항목이 부르는 클로저를 든 대상.
final class StatusMenuTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}
