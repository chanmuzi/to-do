import AppKit

/// 설정 값 버튼에 붙는 메뉴. 창은 포커스를 가져가지 않고 선택 결과를 원래 메뉴 액션으로 돌려준다.
package final class SettingsValueMenu: NSPanel {
    var onDismiss: (() -> Void)?
    private weak var anchor: NSView?
    private let choices: NSMenu
    private var rowsByItem: [NSMenuItem: PickerMenuRow] = [:]
    private var highlighted: PickerMenuRow?
    private var eventMonitor: Any?
    private var outsideMonitor: Any?

    package init?(menu: NSMenu, anchor: NSView, offset: CGSize) {
        guard let host = anchor.window, let screen = host.screen,
              let first = menu.items.compactMap({ $0.view as? PickerMenuRow }).first else { return nil }
        self.anchor = anchor
        choices = menu
        let theme = first.theme
        let padding = theme.component(.settingsPopupGap)
        let width = min(first.preferredWidth, screen.visibleFrame.width)
        let rows = FlippedMenuDocument()
        let innerWidth = width - 2 * padding
        rows.frame.size.width = innerWidth
        var y: CGFloat = 0
        for item in menu.items {
            if let source = item.view as? PickerMenuRow {
                // NSMenuItem은 소유한 뷰의 원점을 되돌린다. 패널에는 같은 항목의 독립된 행을 배치한다.
                let row = source.popupRow(for: item)
                rowsByItem[item] = row
                row.frame = NSRect(x: 0, y: y, width: innerWidth, height: row.bounds.height)
                row.setAccessibilityRole(row.header ? .staticText : .menuItem)
                row.setAccessibilityElement(true)
                row.setAccessibilityLabel(item.title)
                row.setAccessibilityValue(row.selected ? 1 : 0)
                row.setAccessibilityEnabled(item.isEnabled)
                rows.addSubview(row)
                y += row.frame.height
            } else if item.isSeparatorItem {
                let margin = theme.space(.sp1)
                let inset = theme.space(.sp2)
                let line = NSBox(frame: NSRect(x: inset, y: y + margin, width: innerWidth - 2 * inset,
                                               height: theme.shape(.borderWidth)))
                line.boxType = .custom
                line.borderWidth = 0
                line.fillColor = theme.nsColor(.valueMenuRule)
                rows.addSubview(line)
                y += 2 * margin + line.frame.height
            }
        }
        rows.frame.size = NSSize(width: innerWidth, height: y)
        let button = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let gap = offset.height
        let below = button.minY - gap - visible.minY
        let above = visible.maxY - button.maxY - gap
        let desired = y + 2 * padding
        let opensBelow = desired <= below || below >= above
        let height = min(desired, opensBelow ? below : above)
        guard height > 2 * padding else { return nil }
        let x = min(max(visible.minX, button.maxX + offset.width - width), visible.maxX - width)
        let yOrigin = opensBelow ? button.minY - gap - height : button.maxY + gap
        let frame = NSRect(x: x.rounded(), y: yOrigin.rounded(), width: width, height: height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = host.effectiveAppearance
        let surface = MenuSurface(frame: NSRect(origin: .zero, size: frame.size), theme: theme)
        contentView = surface
        surface.setAccessibilityRole(.menu)
        surface.setAccessibilityLabel(anchor.accessibilityLabel())
        let scroll = NSScrollView(frame: surface.bounds.insetBy(dx: padding, dy: padding))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = height < desired
        scroll.scrollerStyle = .overlay
        scroll.documentView = rows
        surface.addSubview(scroll)
        host.addChildWindow(self, ordered: .above)
        orderFront(nil)
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didResignKeyNotification] {
            center.addObserver(self, selector: #selector(dismiss), name: name, object: host)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if self.handleKey(event.keyCode, modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers) { return nil }
                self.close()
            } else {
                self.pointerDown(in: event.window, at: event.locationInWindow, primary: event.type == .leftMouseDown)
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func pointerDown(in window: NSWindow?, at location: NSPoint, primary: Bool) {
        guard window !== self else { return }
        // 값 단추 위에서 시작한 누름은 단추가 뗄 때 한 번만 처리한다.
        if primary, let button = anchor as? ValueButton, window === button.window,
           button.bounds.contains(button.convert(location, from: nil)) { return }
        close()
    }

    package override var canBecomeKey: Bool { false }
    package override var canBecomeMain: Bool { false }

    @objc private func dismiss() { close() }

    package override func close() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        super.close()
        anchor?.needsDisplay = true
        onDismiss?()
        onDismiss = nil
    }

    func highlight(_ row: PickerMenuRow?) {
        let next = row?.choiceItem?.isEnabled == true ? row : nil
        guard next !== highlighted else { return }
        let previous = highlighted
        highlighted = next
        previous?.needsDisplay = true
        next?.needsDisplay = true
    }

    func isHighlighted(_ row: PickerMenuRow) -> Bool { highlighted === row }

    func select(_ row: PickerMenuRow) -> Bool {
        guard let item = row.choiceItem, item.isEnabled else { return false }
        close()
        choices.performActionForItem(at: choices.index(of: item))
        return true
    }

    func handleKey(_ code: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        let available = choices.items.filter { $0.isEnabled && rowsByItem[$0] != nil }
        var next: NSMenuItem?
        switch code {
        case 53: close()
        case 36, 76, 49:
            if let highlighted { _ = select(highlighted) }
        case 125, 126:
            let down = code == 125
            if let item = highlighted?.choiceItem, let index = available.firstIndex(of: item) {
                next = available[(index + available.count + (down ? 1 : -1)) % available.count]
            } else { next = down ? available.first : available.last }
        case 115: next = available.first
        case 119: next = available.last
        case 48: return false
        default:
            guard let prefix = characters, !prefix.isEmpty else { return false }
            next = available.first { $0.title.localizedLowercase.hasPrefix(prefix.localizedLowercase) }
        }
        if let next, let row = rowsByItem[next] {
            highlight(row)
            row.scrollToVisible(row.bounds)
        }
        return true
    }
}

private final class FlippedMenuDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class MenuSurface: NSView {
    private let theme: Theme
    init(frame: NSRect, theme: Theme) {
        self.theme = theme
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let radius = theme.shape(.windowRadius)
        let border = theme.component(.valueMenuBorder)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        theme.nsColor(.surface).withAlphaComponent(1).setFill()
        path.fill()
        path.addClip()
        theme.nsColor(.guide).setStroke()
        path.lineWidth = 2 * border
        path.stroke()
    }
}
