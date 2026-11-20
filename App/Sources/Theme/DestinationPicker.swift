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
                   makeMenu: makeMenu) { item in choose(item.representedObject as? String) }
    }

    private func makeMenu() -> NSMenu {
        let list = NSMenu()
        list.autoenablesItems = false
        list.minimumWidth = theme.component(.menuWidth)
        func add(_ title: String, destination: ScheduleDestination?, id: String?, header: Bool = false, subtitle: String? = nil) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            item.isEnabled = !header
            let selected = !header && selectedID == id
            item.state = selected ? .on : .off
            item.view = PickerMenuRow(theme: theme, text: title, dot: destination?.color.map { Self.dot($0, theme: theme) },
                                       header: header, selected: selected, subtitle: subtitle)
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
    let header: Bool
    let selected: Bool
    let subtitle: String?
    package init(theme: Theme, text: String, dot: NSImage?, header: Bool = false, selected: Bool, subtitle: String? = nil) {
        self.subtitle = subtitle
        self.theme = theme
        self.text = text
        self.dot = dot
        self.header = header
        self.selected = selected
        super.init(frame: CGRect(x: 0, y: 0, width: theme.component(.menuWidth),
                                 height: theme.component(header ? .controlHeight : .segmentHeight)))
        autoresizingMask = [.width]
    }
    @available(*, unavailable)
    package required init?(coder: NSCoder) { fatalError() }
    package override func draw(_ dirtyRect: NSRect) {
        theme.nsColor(.menuSurface).setFill()
        bounds.fill()
        fillEnclosingMenuBackground(with: theme.nsColor(.menuSurface).cgColor)
        let inset = theme.component(.badgeGap)
        if !header, enclosingMenuItem?.isEnabled == true, enclosingMenuItem?.isHighlighted == true {
            theme.nsColor(.menuHighlight).setFill()
            let radius = theme.shape(.controlRadius)
            NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: 0), xRadius: radius, yRadius: radius).fill()
        }
        let gap = theme.space(.sp2)
        var x = inset + gap
        if !header {
            if selected, let check = theme.symbolImage("checkmark", size: .menuIcon)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [theme.nsColor(.text)])) {
                check.draw(at: NSPoint(x: x, y: (bounds.height - check.size.height) / 2),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            x += theme.component(.menuIcon) + gap
            if let dot {
                dot.draw(at: NSPoint(x: x, y: (bounds.height - dot.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                x += dot.size.width + gap
            }
        }
        let value = NSAttributedString(string: text, attributes: [
            .font: theme.nsFont(.body, size: theme.tokens.textStyle(header ? .micro : .ui).size), .foregroundColor: theme.nsColor(header || enclosingMenuItem?.isEnabled == false ? .text3 : .text)])
        value.draw(in: CGRect(x: x, y: (bounds.height - value.size().height) / 2,
                              width: bounds.width - x - inset, height: value.size().height))
        if let subtitle {
            let hint = NSAttributedString(string: subtitle, attributes: [.font: theme.nsFont(.micro), .foregroundColor: theme.nsColor(.text3)])
            let start = x + value.size().width + gap
            hint.draw(in: CGRect(x: start, y: (bounds.height - hint.size().height) / 2,
                                 width: max(0, bounds.width - start - inset), height: hint.size().height))
        }
    }
    package override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
