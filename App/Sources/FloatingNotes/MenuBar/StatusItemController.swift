import AppKit
import Theme

/// 메뉴 막대 아이콘과 그 메뉴(spec 4.3). 메뉴가 열릴 때마다 지금 상태로 다시 채운다
/// ("노트 모두 숨기기"와 "노트 모두 보이기"가 여기서 갈린다).
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let builder: StatusMenuBuilder
    private let areNotesHidden: () -> Bool
    private let perform: (StatusMenuAction) -> Void

    init(
        theme: Theme, icon: NSImage, areNotesHidden: @escaping () -> Bool,
        perform: @escaping (StatusMenuAction) -> Void
    ) {
        builder = StatusMenuBuilder(theme: theme)
        self.areNotesHidden = areNotesHidden
        self.perform = perform
        // 이웃한 아이콘처럼 그림 너비에 맞춘다. 정사각(`squareLength`)은 메뉴 막대 높이만큼 넓어 양옆이 비어 보였다.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel("Float")
        menu.delegate = self
        statusItem.menu = menu
        refill()
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refill()
    }

    /// 지금 메뉴에 놓일 내용.
    var entries: [StatusMenuEntry] {
        StatusMenuModel.entries(areNotesHidden: areNotesHidden())
    }

    /// 확인용: 메뉴 막대에 놓였는지, 아이콘이 템플릿인지.
    var isInstalled: Bool { statusItem.button?.image?.isTemplate == true && statusItem.isVisible }

    /// 확인용: 지금 `NSMenu`에 들어 있는 항목 이름(구분선은 빈 문자열)과 단축키 글자.
    var menuItems: [(title: String, keyEquivalent: String)] {
        refill()
        return menu.items.map { ($0.isSeparatorItem ? "" : $0.title, $0.keyEquivalent) }
    }

    /// 확인용: 메뉴 막대에서 차지하는 너비 방식(`NSStatusItem.variableLength`이어야 한다).
    var length: CGFloat { statusItem.length }

    /// 확인용: 메뉴 막대 아이콘이 놓인 창의 번호(그 창만 찍을 때 쓴다).
    var windowNumber: Int { statusItem.button?.window?.windowNumber ?? 0 }

    /// 확인용: 지금 메뉴에 놓일 줄을 새로 만든 뷰(구분선은 `nil`). 메뉴를 화면에 띄우지 않고 모습을 그려 볼 때 쓴다.
    var detachedRowViews: [NSView?] {
        entries.map { entry in
            guard case .item(let title, let symbol, _) = entry else { return nil }
            return MenuBarRowView(theme: builder.theme, title: title, symbolName: symbol)
        }
    }

    /// 확인용: 메뉴 막대 아이콘을 누른 것처럼 메뉴를 연다(메뉴가 닫힐 때까지 돌아오지 않는다).
    func openMenuForVerification() {
        statusItem.button?.performClick(nil)
    }

    private func refill() {
        builder.fill(menu, with: entries, handler: perform)
    }
}
