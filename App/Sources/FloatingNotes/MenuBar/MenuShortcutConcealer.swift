import AppKit

/// 앱 메뉴에 단축키가 보이지 않게 한다(규칙 4: macOS 메뉴의 기본 단축키 표시도 끈다).
///
/// 시스템은 "편집" 메뉴에 제 항목(이모지 및 기호, 받아쓰기)을 단축키와 함께 끼워 넣는다.
/// 메뉴가 열리기 직전에, 단축키가 적힌 보이는 항목마다 단축키 없는 같은 항목을 앞에 두고 원래 항목은 숨긴다.
/// 숨긴 항목은 `allowsKeyEquivalentWhenHidden`으로 키를 계속 듣는다.
final class MenuShortcutConcealer: NSObject, NSMenuDelegate {
    static let shared = MenuShortcutConcealer()

    func menuNeedsUpdate(_ menu: NSMenu) {
        conceal(in: menu)
    }

    func conceal(in menu: NSMenu) {
        for item in menu.items where !item.isHidden && !item.isSeparatorItem && !item.keyEquivalent.isEmpty {
            guard let visible = item.copy() as? NSMenuItem else { continue }
            visible.keyEquivalent = ""
            visible.keyEquivalentModifierMask = []
            menu.insertItem(visible, at: menu.index(of: item))
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
    }
}
