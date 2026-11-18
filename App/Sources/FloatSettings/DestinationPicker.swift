import AppKit
import Models
import Scheduling
import SwiftUI
import Theme

/// 캘린더의 실제 색을 그대로 담은 이미지로 시스템 팝업과 선택된 메뉴 항목을 함께 그린다.
struct DestinationPicker: NSViewRepresentable {
    let title: String
    let menu: DestinationMenu
    let selectedID: String?
    let theme: Theme
    let choose: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(choose) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.choose = choose
        button.font = theme.nsFont(.row)
        button.setAccessibilityLabel(title)
        let list = NSMenu()
        func add(_ title: String, destination: ScheduleDestination?, id: String?) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            if let color = destination?.color {
                let size = theme.component(.scheduleReminderCircle)
                let ink = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
                let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                    ink.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                    return true
                }
                image.isTemplate = false
                item.image = image
            }
            list.addItem(item)
        }
        add(menu.system.map { "시스템 기본값 (\($0.name))" } ?? "시스템 기본값",
            destination: menu.system, id: nil)
        if !menu.choices.isEmpty { list.addItem(.separator()) }
        for choice in menu.choices { add(choice.destination.name, destination: choice.destination, id: choice.id) }
        button.menu = list
        button.select(list.items.first { !$0.isSeparatorItem && ($0.representedObject as? String) == selectedID })
        button.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject {
        var choose: (String?) -> Void
        init(_ choose: @escaping (String?) -> Void) { self.choose = choose }
        @objc func select(_ sender: NSPopUpButton) { choose(sender.selectedItem?.representedObject as? String) }
    }
}
