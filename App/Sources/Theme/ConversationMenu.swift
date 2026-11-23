import SwiftUI

package struct ConversationMenu: NSViewRepresentable {
    package let theme: Theme
    package let id: UUID
    package let enabled: Bool
    package let revealed: Bool
    package var open: (() -> Void)?
    let visibilityChanged: (Bool) -> Void
    package let rename: () -> Void
    package let delete: () -> Void

    package init(theme: Theme, id: UUID, enabled: Bool = true, revealed: Bool = true, open: (() -> Void)? = nil,
                 visibilityChanged: @escaping (Bool) -> Void = { _ in }, rename: @escaping () -> Void, delete: @escaping () -> Void) {
        self.theme = theme
        self.id = id
        self.enabled = enabled
        self.revealed = revealed
        self.open = open
        self.visibilityChanged = visibilityChanged
        self.rename = rename
        self.delete = delete
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, nsView: ConversationMenuButton, context: Context) -> CGSize? {
        let side = theme.component(.iconButton)
        return CGSize(width: side, height: side)
    }

    package func makeNSView(context: Context) -> ConversationMenuButton { ConversationMenuButton() }
    package func updateNSView(_ button: ConversationMenuButton, context: Context) {
        button.commands = self
        button.image = theme.symbolImage("ellipsis", size: .iconMedium)
        button.contentTintColor = theme.nsColor(.text2)
        button.setAccessibilityLabel("더 보기")
        button.setAccessibilityElement(true)
        button.needsDisplay = true
    }
}

package final class ConversationMenuButton: NSButton {
    fileprivate var commands: ConversationMenu?
    private var hovered = false
    private var popup: NSPanel? {
        didSet {
            if let oldValue { NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: oldValue) }
            if let popup {
                NotificationCenter.default.addObserver(self, selector: #selector(popupClosing), name: NSWindow.willCloseNotification, object: popup)
                commands?.visibilityChanged(true)
            }
        }
    }
    @objc private func popupClosing() { commands?.visibilityChanged(false); needsDisplay = true }
    package var conversationID: UUID? { commands?.id }
    private var visibleIcon: Bool { commands?.revealed == true || popup?.isVisible == true }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        target = self
        action = #selector(showMenu)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    package override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    package override func draw(_ dirtyRect: NSRect) {
        guard visibleIcon, let theme = commands?.theme else { return }
        if hovered || popup?.isVisible == true {
            theme.nsColor(.hover).setFill()
            let radius = theme.shape(.controlRadius)
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
    package override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    package override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    package override func hitTest(_ point: NSPoint) -> NSView? { visibleIcon ? super.hitTest(point) : nil }

    @objc package func showMenu() {
        guard let commands else { return }
        popup?.close()
        let theme = commands.theme
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ symbol: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = commands.enabled
            let image = theme.symbolImage(symbol, size: .iconSmall)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [theme.nsColor(commands.enabled ? .text2 : .text3)]))
            item.view = PickerMenuRow(theme: theme, text: title, dot: image,
                                      selected: false, width: theme.component(.agentMenuWidth) + theme.component(.agentFaceLarge) + theme.component(.agentProgressHeight),
                                      command: true)
        }
        if commands.open != nil { add("열기", "macwindow", #selector(openConversation)) }
        add("이름 바꾸기", "pencil", #selector(beginRename))
        menu.addItem(.separator())
        add("지우기", "trash", #selector(confirmDeletion))
        popup = SettingsValueMenu(menu: menu, anchor: self, offset: CGSize(width: 0, height: theme.space(.sp1)))
        needsDisplay = true
    }

    @objc private func openConversation() { commands?.open?() }
    @objc package func beginRename() {
        guard let commands, commands.enabled else { return }
        popup?.close()
        commands.rename()
    }
    @objc package func confirmDeletion() {
        guard let commands, commands.enabled else { return }
        popup?.close()
        popup = ConfirmationPopover(theme: commands.theme, anchor: self, title: "대화를 삭제할까요?",
                                    detail: "이미 받은 제안과 노트는 그대로 남습니다.", confirmTitle: "삭제", confirm: commands.delete)
    }

    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { popup?.close(); popup = nil }
    }
}

extension NSView {
    package func conversationButton(_ id: UUID) -> ConversationMenuButton? {
        if let button = self as? ConversationMenuButton, button.conversationID == id { return button }
        return subviews.lazy.compactMap { $0.conversationButton(id) }.first
    }
}
