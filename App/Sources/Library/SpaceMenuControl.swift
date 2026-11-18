import AppKit
import Models
import SwiftUI
import Theme

/// 오른쪽 클릭과 더 보기 버튼이 같은 시스템 메뉴를 사용한다.
struct SpaceMenuControl: NSViewRepresentable {
    let model: LibraryModel
    let space: Space
    let rename: () -> Void
    let delete: () -> Void
    let contextOnly: Bool

    func makeNSView(context: Context) -> SpaceMenuButton {
        let button = SpaceMenuButton()
        button.isBordered = false
        button.title = ""
        button.target = button
        button.action = #selector(SpaceMenuButton.openMenu)
        button.contextOnly = contextOnly
        button.setAccessibilityElement(!contextOnly)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpaceMenuButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateNSView(_ button: SpaceMenuButton, context: Context) {
        button.setAccessibilityLabel(contextOnly ? nil : "\(space.name) 더 보기")
        button.image = contextOnly ? nil : model.theme.symbolImage("ellipsis", size: .menuIcon)
        button.imagePosition = .imageOnly
        button.contentTintColor = model.theme.nsColor(.text2)
        button.control = self
        button.menu = button.spaceMenu()
    }
}

final class SpaceMenuButton: NSButton {
    var contextOnly = false
    var control: SpaceMenuControl?
    override var acceptsFirstResponder: Bool { !contextOnly }
    override func draw(_ dirtyRect: NSRect) {
        if !contextOnly { super.draw(dirtyRect) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if contextOnly {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
        }
        return super.hitTest(point)
    }

    func spaceMenu() -> NSMenu {
        let menu = NSMenu()
        guard let control else { return menu }
        func separate() {
            let item = NSMenuItem.separator()
            item.view = MenuBarSeparatorView(theme: control.model.theme)
            menu.addItem(item)
        }
        func add(_ title: String, _ symbol: String, _ selector: Selector) {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
            item.target = self
            item.styleLibraryCommand(symbol, theme: control.model.theme)
        }
        add("이 스페이스에 새 노트", "doc.badge.plus", #selector(createNote))
        separate()
        add("아이콘 바꾸기", "photo", #selector(changeIcon))
        add("이름 바꾸기", "pencil", #selector(rename))
        separate()
        add("스페이스 지우기", "trash", #selector(deleteSpace))
        return menu
    }

    @objc func openMenu() { menu?.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY), in: self) }
    @objc private func createNote() {
        if let control { control.model.newNote(in: control.space.id) }
    }
    @objc private func changeIcon() { control?.model.iconSpace = control?.space.id }
    @objc private func rename() { control?.rename() }
    @objc private func deleteSpace() { control?.delete() }
}
