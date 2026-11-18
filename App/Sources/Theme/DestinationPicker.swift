import AppKit
import Models
import SwiftUI

package struct DestinationPicker: View {
    let title: String
    let choices: [CalendarChoice]
    let current: ScheduleDestination?
    let includesDefault: Bool
    let selectedID: String?
    let theme: Theme
    let choose: (String?) -> Void

    package init(title: String, choices: [CalendarChoice], current: ScheduleDestination?, selectedID: String?,
                 includesDefault: Bool = true, theme: Theme, choose: @escaping (String?) -> Void) {
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
        ValuePopup(label: title, value: destination?.name ?? "시스템 기본값",
                   dot: destination?.color.map { Self.dot($0, theme: theme) }, theme: theme,
                   makeMenu: makeMenu) { item in choose(item.representedObject as? String) }
    }

    private func makeMenu() -> NSMenu {
        let list = NSMenu()
        list.autoenablesItems = false
        list.minimumWidth = theme.component(.menuWidth)
        func add(_ title: String, destination: ScheduleDestination?, id: String?, header: Bool = false) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            item.isEnabled = !header
            let selected = !header && selectedID == id
            item.state = selected ? .on : .off
            item.view = DestinationRow(theme: theme, text: title, dot: destination?.color.map { Self.dot($0, theme: theme) },
                                       header: header, selected: selected)
            list.addItem(item)
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
        if includesDefault {
            if !list.items.isEmpty { list.addItem(.separator()) }
            add("시스템 기본값", destination: nil, id: nil)
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

private final class DestinationRow: NSView {
    let theme: Theme
    let text: String
    let dot: NSImage?
    let header: Bool
    let selected: Bool
    init(theme: Theme, text: String, dot: NSImage?, header: Bool, selected: Bool) {
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
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        theme.nsColor(.surface).setFill()
        bounds.fill()
        fillEnclosingMenuBackground(with: theme.nsColor(.surface).cgColor)
        let inset = theme.component(.badgeGap)
        if !header, enclosingMenuItem?.isHighlighted == true {
            theme.nsColor(.selected).setFill()
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
            .font: theme.nsFont(.body, size: theme.tokens.textStyle(header ? .micro : .ui).size), .foregroundColor: theme.nsColor(header ? .text3 : .text)])
        value.draw(in: CGRect(x: x, y: (bounds.height - value.size().height) / 2,
                              width: bounds.width - x - inset, height: value.size().height))
    }
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
