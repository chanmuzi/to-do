import AppKit
import SwiftUI
import Theme

/// 색 줄의 +만 보이고, 누르면 시스템 색상 패널에서 직접 고른다.
struct SymbolColorButton: NSViewRepresentable {
    let theme: Theme
    let changed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "직접 고르기")!,
                              target: context.coordinator, action: #selector(Coordinator.open))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("직접 고르기")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.contentTintColor = theme.nsColor(.text3)
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "직접 고르기")?
            .withSymbolConfiguration(.init(pointSize: theme.component(.iconSmall), weight: .regular))
        context.coordinator.changed = changed
    }
    final class Coordinator: NSObject {
        private static var active: Coordinator?
        private var closeObserver: (any NSObjectProtocol)?
        isolated deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
        var changed: (String) -> Void
        init(changed: @escaping (String) -> Void) { self.changed = changed }
        @objc func open() {
            let panel = NSColorPanel.shared
            Self.active = self
            if closeObserver == nil {
                closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                    object: panel, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if Self.active === self { Self.active = nil; panel.setTarget(nil) }
                    }
                }
            }
            panel.showsAlpha = false
            panel.isContinuous = true
            panel.setTarget(self); panel.setAction(#selector(picked))
            panel.orderFront(nil)
        }
        @objc func picked(_ panel: NSColorPanel) {
            guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
            changed(String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255)))
        }
    }
}
