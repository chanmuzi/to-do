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
                   dot: destination?.color.map { Self.dot($0, theme: theme) }, theme: theme, inSettings: inSettings, fillsRow: !inSettings,
                   menuOffset: CGSize(width: theme.space(.sp3), height: theme.space(.sp1)), makeMenu: makeMenu) { item in choose(item.representedObject as? String) }
    }

    private func makeMenu() -> NSMenu {
        let list = NSMenu()
        list.autoenablesItems = false
        list.minimumWidth = theme.component(inSettings ? .calendarMenuWidth : .noteMenuWidth)
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
            if !list.items.isEmpty { list.addItem(MenuSeparatorView.item(theme: theme)) }
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
