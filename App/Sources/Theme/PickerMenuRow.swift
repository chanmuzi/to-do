import AppKit

package final class PickerMenuRow: NSView {
    let theme: Theme
    let text: String
    let dot: NSImage?
    private(set) weak var choiceItem: NSMenuItem?
    let preferredWidth: CGFloat
    let header: Bool
    let selected: Bool
    let subtitle: String?
    let command: Bool
    package init(theme: Theme, text: String, dot: NSImage?, header: Bool = false, selected: Bool, subtitle: String? = nil, width: CGFloat? = nil, command: Bool = false) {
        self.command = command
        self.preferredWidth = width ?? theme.component(.menuWidth)
        self.subtitle = subtitle
        self.theme = theme
        self.text = text
        self.dot = dot
        self.header = header
        self.selected = selected
        super.init(frame: CGRect(x: 0, y: 0, width: preferredWidth,
                                 height: theme.component(.rowHeight)))
        wantsLayer = true
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }
    @available(*, unavailable)
    package required init?(coder: NSCoder) { fatalError() }
    package var textFont: NSFont {
        theme.nsFont(.body, size: theme.tokens.textStyle(.ui).size)
    }

    package static func widthToFitTitles(_ titles: [String], minimum: CGFloat, theme: Theme) -> CGFloat {
        let font = theme.nsFont(.body, size: theme.tokens.textStyle(.ui).size)
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(minimum, 2 * theme.space(.sp3) + theme.component(.iconLarge) + theme.space(.sp2) + ceil(widest))
    }

    func popupRow(for item: NSMenuItem) -> PickerMenuRow {
        let row = PickerMenuRow(theme: theme, text: text, dot: dot, header: header, selected: selected,
                                subtitle: subtitle, width: preferredWidth, command: command)
        row.choiceItem = item
        return row
    }

    var titleOriginX: CGFloat {
        let inset = theme.space(.sp1) + theme.space(.sp2)
        guard !header else { return inset }
        let pastColumn = inset + theme.component(.iconLarge) + theme.space(.sp2)
        return pastColumn + (command ? 0 : dot.map { $0.size.width + theme.space(.sp2) } ?? 0)
    }

    package override func draw(_ dirtyRect: NSRect) {
        let popup = window as? SettingsValueMenu
        let item = choiceItem ?? enclosingMenuItem
        let edge = theme.space(.sp1)
        let gap = theme.space(.sp2)
        let column = theme.component(.iconLarge)
        if popup == nil {
            updateLayer()
            theme.nsColor(.surface).setFill()
            bounds.fill()
        }
        if !header, item?.isEnabled == true, popup?.isHighlighted(self) ?? (item?.isHighlighted == true) {
            theme.nsColor(.hover).setFill()
            let radius = theme.shape(.chipRadius)
            NSBezierPath(roundedRect: bounds.insetBy(dx: edge, dy: 0), xRadius: radius, yRadius: radius).fill()
        }
        var x = edge + gap
        let right = bounds.maxX - x
        if !header {
            let check = selected ? theme.symbolImage("checkmark", size: .menuIcon)?.withSymbolConfiguration(
                .init(paletteColors: [theme.nsColor(.text)])) : nil
            if let image = command ? dot : check {
                image.draw(at: NSPoint(x: x + (column - image.size.width) / 2, y: bounds.midY - image.size.height / 2),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            x += column + gap
            if !command, let dot {
                dot.draw(at: NSPoint(x: x, y: bounds.midY - dot.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        x = titleOriginX
        let ink: ColorToken = header || item?.isEnabled == false ? .text3 : .text
        var titleEnd = right
        if let subtitle {
            let hintFont = theme.nsFont(.body, size: theme.tokens.textStyle(.micro).size)
            let hintWidth = min((subtitle as NSString).size(withAttributes: [.font: hintFont]).width, max(0, (right - x) / 2))
            MenuText.draw(subtitle, font: hintFont, color: theme.nsColor(.text3), x: right - hintWidth,
                          width: hintWidth, center: bounds.midY, flipped: isFlipped)
            titleEnd -= hintWidth + gap
        }
        MenuText.draw(text, font: textFont, color: theme.nsColor(ink), x: x,
                      width: titleEnd - x, center: bounds.midY, flipped: isFlipped)
    }

    package override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = theme.nsColor(.surface).cgColor
            layer?.backgroundColor = color
            if enclosingMenuItem != nil { fillEnclosingMenuBackground(with: color) }
        }
    }

    package override func mouseEntered(with event: NSEvent) { (window as? SettingsValueMenu)?.highlight(self) }
    package override func mouseExited(with event: NSEvent) {
        if let popup = window as? SettingsValueMenu, popup.isHighlighted(self) { popup.highlight(nil) }
    }
    package override func accessibilityPerformPress() -> Bool {
        (window as? SettingsValueMenu)?.select(self) ?? super.accessibilityPerformPress()
    }
    package override func mouseUp(with event: NSEvent) {
        if let popup = window as? SettingsValueMenu { _ = popup.select(self); return }
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
