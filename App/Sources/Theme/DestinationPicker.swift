import AppKit
import Models
import SwiftUI

package struct DestinationPicker: View {
    let title: String
    let choices: [CalendarChoice]
    let current: ScheduleDestination?
    let inSettings: Bool
    let includesDefault: Bool
    let selectedID: String?
    let theme: Theme
    let choose: (String?) -> Void

    package init(title: String, choices: [CalendarChoice], current: ScheduleDestination?, selectedID: String?,
                 includesDefault: Bool = true, inSettings: Bool = false, theme: Theme, choose: @escaping (String?) -> Void) {
        self.inSettings = inSettings
        self.title = title
        self.choices = choices
        self.current = current
        self.selectedID = selectedID
        self.includesDefault = includesDefault
        self.theme = theme
        self.choose = choose
    }

    package var body: some View {
        let destination = choices.first { $0.id == selectedID }?.destination ?? current
        ValuePopup(label: title, value: destination?.name ?? "캘린더 앱 기본값",
                   dot: destination?.color.map { Self.dot($0, theme: theme) }, theme: theme, inSettings: inSettings,
                   menuOffset: CGSize(width: theme.space(.sp3), height: theme.space(.sp1)), makeMenu: makeMenu) { item in choose(item.representedObject as? String) }
    }

    private func makeMenu() -> NSMenu {
        let list = NSMenu()
        list.autoenablesItems = false
        list.minimumWidth = theme.component(inSettings ? .calendarMenuWidth : .menuWidth)
        func add(_ title: String, destination: ScheduleDestination?, id: String?, header: Bool = false, subtitle: String? = nil) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            item.isEnabled = !header
            let selected = !header && selectedID == id
            item.state = selected ? .on : .off
            item.view = PickerMenuRow(theme: theme, text: title, dot: destination?.color.map { Self.dot($0, theme: theme) },
                                       header: header, selected: selected, subtitle: subtitle, width: list.minimumWidth)
            list.addItem(item)
        }
        if includesDefault {
            add("캘린더 앱 기본값", destination: nil, id: nil, subtitle: current?.name)
        }
        var seen: Set<String> = []
        let accounts = choices.map(\.account).filter { seen.insert($0).inserted }
        for account in accounts {
            if !list.items.isEmpty { list.addItem(.separator()) }
            if !account.isEmpty { add(account, destination: nil, id: nil, header: true) }
            for choice in choices where choice.account == account {
                add(choice.destination.name, destination: choice.destination, id: choice.id)
            }
        }
        return list
    }

    private static func dot(_ color: ScheduleDestination.Color, theme: Theme) -> NSImage {
        let size = theme.component(.menuDot)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

}

package final class PickerMenuRow: NSView {
    let theme: Theme
    let text: String
    let dot: NSImage?
    private(set) weak var choiceItem: NSMenuItem?
    let preferredWidth: CGFloat
    let header: Bool
    let selected: Bool
    let subtitle: String?
    package init(theme: Theme, text: String, dot: NSImage?, header: Bool = false, selected: Bool, subtitle: String? = nil, width: CGFloat? = nil) {
        self.preferredWidth = width ?? theme.component(.menuWidth)
        self.subtitle = subtitle
        self.theme = theme
        self.text = text
        self.dot = dot
        self.header = header
        self.selected = selected
        super.init(frame: CGRect(x: 0, y: 0, width: preferredWidth,
                                 height: theme.component(header ? .controlHeight : .segmentHeight)))
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }
    @available(*, unavailable)
    package required init?(coder: NSCoder) { fatalError() }
    package var textFont: NSFont {
        if choiceItem != nil {
            return NSFont.systemFont(ofSize: theme.tokens.textStyle(header ? .librarySection : .rowSub).size,
                                     weight: header ? .medium : .regular)
        }
        return theme.nsFont(.body, size: theme.tokens.textStyle(header ? .micro : .ui).size)
    }

    func popupRow(for item: NSMenuItem) -> PickerMenuRow {
        let row = PickerMenuRow(theme: theme, text: text, dot: dot, header: header, selected: selected,
                                subtitle: subtitle, width: preferredWidth)
        row.choiceItem = item
        return row
    }

    package override func draw(_ dirtyRect: NSRect) {
        let popup = window as? SettingsValueMenu
        let item = choiceItem ?? enclosingMenuItem
        let inset = popup == nil ? theme.component(.badgeGap) : 0
        if popup == nil {
            theme.nsColor(.menuSurface).setFill()
            bounds.fill()
            fillEnclosingMenuBackground(with: theme.nsColor(.menuSurface).cgColor)
        }
        if !header, item?.isEnabled == true, popup?.isHighlighted(self) ?? (item?.isHighlighted == true) {
            theme.nsColor(.menuHighlight).setFill()
            let radius = popup == nil ? theme.shape(.controlRadius) : theme.component(.browseRowRadius)
            NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: 0), xRadius: radius, yRadius: radius).fill()
        }
        let gap = theme.space(.sp2)
        var x = inset + gap
        if !header {
            let checkSize: ComponentToken = popup == nil ? .menuIcon : .valueMenuCheck
            if selected, popup != nil {
                drawValueCheck(at: x)
            } else if selected, let check = theme.symbolImage("checkmark", size: checkSize)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [theme.nsColor(.text)])) {
                check.draw(at: NSPoint(x: x + (theme.component(checkSize) - check.size.width) / 2, y: (bounds.height - check.size.height) / 2),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            x += theme.component(checkSize) + gap
            if let dot {
                let opacity = popup != nil && item?.isEnabled == false ? theme.ratio(.disabledIconOpacity) : 1
                dot.draw(at: NSPoint(x: x, y: (bounds.height - dot.size.height) / 2),
                         from: .zero, operation: .sourceOver, fraction: opacity)
                x += dot.size.width + gap
            }
        }
        let ink: ColorToken = header || (popup == nil && item?.isEnabled == false) ? .text3 : (item?.isEnabled == false ? .valueMenuDisabled : .text)
        let value = NSAttributedString(string: text, attributes: [.font: textFont, .foregroundColor: theme.nsColor(ink)])
        value.draw(in: CGRect(x: x, y: (bounds.height - value.size().height) / 2,
                              width: bounds.width - x - inset, height: value.size().height))
        if let subtitle {
            let hint = NSAttributedString(string: subtitle, attributes: [.font: theme.nsFont(.micro), .foregroundColor: theme.nsColor(.text3)])
            let afterTitle = x + value.size().width + gap
            let start = popup == nil ? afterTitle : max(afterTitle, bounds.width - gap - hint.size().width)
            hint.draw(in: CGRect(x: start, y: (bounds.height - hint.size().height) / 2,
                                 width: max(0, bounds.width - start - inset), height: hint.size().height))
        }
    }
    /// 시안의 16단위 벡터를 체크 칸에 맞춰 그린다. AppKit 행의 y축은 위를 향한다.
    private func drawValueCheck(at x: CGFloat) {
        let size = theme.component(.valueMenuCheck)
        let unit = size / 16
        func point(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint {
            NSPoint(x: x + dx * unit, y: bounds.midY + size / 2 - dy * unit)
        }
        let path = NSBezierPath()
        path.move(to: point(3, 8.5))
        path.line(to: point(6.2, 11.7))
        path.line(to: point(13, 4.8))
        path.lineWidth = 1.9 * unit
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        theme.nsColor(.text).setStroke()
        path.stroke()
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
