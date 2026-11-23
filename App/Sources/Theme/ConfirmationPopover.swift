import SwiftUI

/// 확인을 기다리는 동안에도 키 창과 입력 초점은 원래 창에 둔다.
package final class ConfirmationPopover: NSPanel {
    private var monitor: Any?
    private var outsideMonitor: Any?

    package init?(theme: Theme, anchor: NSView, title: String, detail: String,
                  confirmTitle: String, confirm: @escaping () -> Void) {
        guard let host = anchor.window, let screen = host.screen else { return nil }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        appearance = host.effectiveAppearance
        hasShadow = true
        let view = NSHostingView(rootView: ConfirmationContent(theme: theme, title: title, detail: detail,
            confirmTitle: confirmTitle, cancel: { [weak self] in self?.close() }, confirm: { [weak self] in
                self?.close()
                confirm()
            }))
        let size = view.fittingSize
        let rect = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let gap = theme.space(.sp1)
        let visible = screen.visibleFrame
        let below = rect.minY - gap - size.height
        let y = below >= visible.minY ? below : min(rect.maxY + gap, visible.maxY - size.height)
        contentView = view
        let x = min(max(visible.minX, rect.maxX - size.width), visible.maxX - size.width)
        setFrame(NSRect(x: x.rounded(),
                        y: y.rounded(), width: size.width, height: size.height), display: false)
        host.addChildWindow(self, ordered: .above)
        orderFront(nil)
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(dismiss), name: name, object: host)
        }
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown { return self.handleKey(event.keyCode) ? nil : event }
            self.pressed(in: event.window)
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouse) { [weak self] _ in self?.close() }
    }

    package func handleKey(_ code: UInt16) -> Bool {
        if code == 53 { close(); return true }
        return code == 36 || code == 76
    }

    package func pressed(in window: NSWindow?) {
        if window !== self { close() }
    }

    @objc private func dismiss() { close() }
    package override var canBecomeKey: Bool { false }
    package override var canBecomeMain: Bool { false }

    package override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        monitor = nil
        outsideMonitor = nil
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        super.close()
    }
}

private struct ConfirmationContent: View {
    let theme: Theme
    let title: String
    let detail: String
    let confirmTitle: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
            Text(title)
                .font(theme.font(.body, size: theme.tokens.textStyle(.title).size, weight: theme.tokens.textStyle(.selected).weight))
                .foregroundStyle(theme.color(.text))
                .frame(minHeight: theme.component(.agentProgressHeight))
            Text(detail).font(theme.font(.rowSub)).foregroundStyle(theme.color(.text2))
                .frame(minHeight: theme.component(.agentProgressHeight))
            HStack(spacing: theme.component(.chromeGap)) {
                Spacer()
                Button("취소", action: cancel).buttonStyle(WhiteControl(theme: theme))
                Button(confirmTitle, action: confirm).buttonStyle(WhiteControl(theme: theme, ink: .warn))
            }.padding(.top, theme.space(.sp3) - theme.component(.iconButtonGap))
        }
        .padding(theme.space(.sp3))
        .frame(width: theme.component(.upcomingWidth) + theme.component(.agentFaceLarge))
        .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
        .fixedSize(horizontal: false, vertical: true)
    }
}
