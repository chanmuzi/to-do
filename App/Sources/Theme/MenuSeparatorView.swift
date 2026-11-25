import AppKit

/// 더 보기 메뉴의 구분선(spec 5.4). 시스템 구분선은 메뉴의 반투명 바탕 위에 그려져 뒤가 비치므로,
/// 줄과 같은 불투명 `surface` 바탕 위에 1px `line`을 직접 긋는다.
package final class MenuSeparatorView: NSView {
    private let theme: Theme
    private let rule = NSView()

    package init(theme: Theme) {
        self.theme = theme
        super.init(frame: NSRect(
            x: 0, y: 0, width: theme.component(.noteMenuWidth), height: theme.space(.sp2) + theme.shape(.borderWidth)
        ))
        wantsLayer = true
        autoresizingMask = [.width]
        rule.wantsLayer = true
        addSubview(rule)
        setAccessibilityElement(false)
    }

    package static func item(theme: Theme) -> NSMenuItem {
        let item = NSMenuItem.separator()
        item.view = MenuSeparatorView(theme: theme)
        return item
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    package override var wantsUpdateLayer: Bool { true }

    package override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = theme.nsColor(.surface).cgColor
            rule.layer?.backgroundColor = theme.nsColor(.line).cgColor
        }
    }

    package override func layout() {
        super.layout()
        let inset = theme.space(.sp1) + theme.space(.sp2)
        let width = theme.shape(.borderWidth)
        rule.frame = NSRect(
            x: inset, y: ((bounds.height - width) / 2).rounded(), width: max(0, bounds.width - inset * 2), height: width
        )
    }
}
