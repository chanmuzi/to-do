import AppKit
import Models
import SwiftUI
import Theme

/// 키 입력은 이 창에만 전달한다. 바깥 클릭은 원래 목적지에도 전달한다.
final class AgentContextPanel: NSPanel {
    @Observable final class Placement {
        var edge = AttachedBubble.Edge.top
        var tip: CGFloat = 0
    }
    let model: AgentContextPickerModel
    private let placement = Placement()
    private let theme: Theme
    private weak var anchor: NSView?
    private var local: Any?
    private var outside: Any?
    private var bodySize = CGSize.zero
    private let acceptsKeys: Bool
    private var hostFrame: CGRect
    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }

    init?(draft: AgentDraft, controls: AgentContextControls, theme: Theme, allowsKey: Bool) {
        guard let anchor = draft.contextAnchor, let host = anchor.window, let screen = host.screen else { return nil }
        hostFrame = host.frame
        self.anchor = anchor
        self.theme = theme
        acceptsKeys = allowsKey
        model = AgentContextPickerModel(draft: draft, catalog: controls.catalog())
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = host.effectiveAppearance
        let padding = shadowInset
        let view = AgentContextPickerView(model: model, controls: controls, theme: theme,
                                          maxHeight: screen.visibleFrame.height * theme.ratio(.browseMaxScreenHeight),
                                          close: { [weak self] in self?.close() })
            .background(PickerBubble(theme: theme, placement: placement))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                self?.position(body: size)
            }
            .padding(padding)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.sizingOptions = []
        contentView = hosting
        position(body: CGSize(width: size.width - 2 * padding, height: size.height - 2 * padding))
        host.addChildWindow(self, ordered: .above)
        if allowsKey { makeKeyAndOrderFront(nil) } else { orderFront(nil) }
        for name in [NSWindow.willMoveNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(hostChanged(_:)), name: name, object: host)
        }
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        local = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            if event.type != .keyDown {
                let body = CGRect(origin: .init(x: padding, y: padding), size: bodySize)
                if let anchor = self.anchor, event.window === anchor.window,
                   anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
                if event.window !== self || !body.contains(event.locationInWindow) { close() }
            } else if event.window === self, (firstResponder as? NSTextView)?.hasMarkedText() != true,
                      handleKey(event.keyCode, modifiers: event.modifierFlags) { return nil }
            return event
        }
        outside = NSEvent.addGlobalMonitorForEvents(matching: mouse) { [weak self] _ in self?.close() }
    }

    private var shadowInset: CGFloat {
        let shadow = theme.shadow(.pop).last
        return (shadow?.blur ?? 0) + abs(shadow?.y ?? 0) + theme.component(.chromePaddingEnd)
    }

    func reposition() { position(body: bodySize) }

    private func position(body: CGSize) {
        guard body.width > 0, body.height > 0, let anchor, let host = anchor.window,
              let screen = host.screen?.visibleFrame else { return }
        let rect = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let tail = theme.component(.chromePaddingEnd)
        let below = rect.minY - tail - body.height
        let above = below < screen.minY && screen.maxY - rect.maxY > rect.minY - screen.minY
        let x = min(max(screen.minX, rect.midX - body.width / 2), screen.maxX - body.width)
        let y = min(max(screen.minY, above ? rect.maxY + tail : below), screen.maxY - body.height)
        bodySize = body
        placement.edge = above ? .bottom : .top
        placement.tip = rect.midX - x
        let frame = CGRect(origin: .init(x: x, y: y), size: body).insetBy(dx: -shadowInset, dy: -shadowInset)
        if self.frame != frame { setFrame(frame, display: true) }
    }

    func handleKey(_ key: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection([.command, .shift, .control, .option])
        if key == 53 { close(); return true }
        guard !model.choosingDay else { return false }
        switch (key, flags) {
        case (36, .command), (76, .command): model.toggle(model.selection)
        case (36, []), (76, []): close()
        case (125, []): model.move(1)
        case (126, []): model.move(-1)
        case (124, []):
            guard case .item(.space(let id)) = model.selection else { return false }
            model.enter(id)
        case (123, []):
            guard model.space != nil else { return false }
            model.back()
        default: return false
        }
        return true
    }

    @objc private func hostChanged(_ notification: Notification) {
        if notification.name == NSWindow.didMoveNotification, let host = anchor?.window,
           host.frame.size != hostFrame.size {
            hostFrame = host.frame
            reposition()
        } else { close() }
    }
    override func close() {
        if let local { NSEvent.removeMonitor(local) }
        if let outside { NSEvent.removeMonitor(outside) }
        local = nil
        outside = nil
        NotificationCenter.default.removeObserver(self)
        if model.draft.contextPanel === self { model.draft.contextPanel = nil }
        parent?.removeChildWindow(self)
        super.close()
        contentView = nil
    }
}

private struct PickerBubble: View {
    let theme: Theme
    let placement: AgentContextPanel.Placement
    var body: some View {
        AttachedBubble(theme: theme, edge: placement.edge, tip: placement.tip, radius: theme.component(.browseRadius))
    }
}
