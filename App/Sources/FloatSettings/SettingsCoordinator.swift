import AppKit
import SwiftUI
import Theme

package final class SettingsCoordinator: NSObject, NSWindowDelegate {
    package let model: SettingsModel
    private let theme: Theme
    package var allowsKeyWindows = true
    package private(set) var window: NSWindow?

    package init(model: SettingsModel, theme: Theme) {
        self.model = model
        self.theme = theme
    }

    package func show(_ pane: SettingsPane? = nil) {
        model.pane = pane ?? .general
        model.refreshCalendars()
        if window == nil {
            let size = NSSize(width: theme.component(.settingsWidth), height: theme.component(.settingsContentHeight))
            let panel = SettingsWindow(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "설정"
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.titlebarSeparatorStyle = .none
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                panel.standardWindowButton(button)?.isHidden = true
            }
            panel.isMovableByWindowBackground = true
            panel.allowsKey = allowsKeyWindows
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            let view = SettingsView(model: model, theme: theme, reset: { [weak self] in self?.confirmReset() },
                                    close: { [weak panel] in panel?.close() }).ignoresSafeArea()
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            panel.contentView = host
            if !allowsKeyWindows, let screen = NSScreen.screens.last {
                panel.setFrameOrigin(screen.visibleFrame.origin)
            } else { panel.center() }
            window = panel
        }
        if allowsKeyWindows {
            window?.makeKeyAndOrderFront(nil)
            window?.makeMain()
        } else { window?.orderFrontRegardless() }
    }

    package func windowWillClose(_ notification: Notification) { model.agents?.cancel() }

    package func confirmReset() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "모든 설정을 기본값으로 되돌릴까요?"
        alert.informativeText = "노트와 일정은 그대로예요."
        alert.addButton(withTitle: "되돌리기")
        alert.addButton(withTitle: "취소").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn, let self { model.restoreDefaults(theme: theme) }
        }
    }
}

private final class SettingsWindow: NSWindow {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if attachedSheet == nil && ((modifiers.isEmpty && event.keyCode == 53) ||
            (modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w")) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { if attachedSheet == nil { close() } }
    override func performClose(_ sender: Any?) { if attachedSheet == nil { close() } }
}
