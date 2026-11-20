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
        model.agents?.refresh()
        model.showsInstallTip = false
        if window == nil {
            let size = NSSize(width: theme.component(.settingsWidth), height: theme.component(.settingsContentHeight))
            let panel = SettingsWindow(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "설정"
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.titlebarSeparatorStyle = .none
            panel.standardWindowButton(.zoomButton)?.isEnabled = false
            panel.dismissReset = { [weak model] in
                guard model?.confirmingReset == true else { return false }
                model?.confirmingReset = false
                return true
            }
            panel.isMovableByWindowBackground = true
            panel.allowsKey = allowsKeyWindows
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            let view = SettingsView(model: model, theme: theme).ignoresSafeArea()
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            panel.contentView = host
            panel.initialFirstResponder = host
            if !allowsKeyWindows, let screen = NSScreen.screens.last {
                panel.setFrameOrigin(screen.visibleFrame.origin)
            } else { panel.center() }
            window = panel
        }
        if allowsKeyWindows {
            window?.makeKeyAndOrderFront(nil)
            window?.makeMain()
            window?.makeFirstResponder(window)
        } else { window?.orderFrontRegardless() }
    }

    package func showAgent(_ provider: String) {
        guard let engine = model.agents?.engines.first(where: { $0.provider.rawValue == provider }) else { return }
        model.detailEngine = engine
        show(.accounts)
    }

    package func windowDidBecomeKey(_ notification: Notification) { model.agents?.refreshMissing() }

    package func windowWillClose(_ notification: Notification) {
        model.confirmingReset = false
        model.detailEngine = nil
        model.agents?.close()
    }

    package func confirmReset() { model.confirmingReset = true }

    package func answerReset(_ restore: Bool) {
        guard model.confirmingReset else { return }
        model.confirmingReset = false
        if restore { model.restoreDefaults(theme: theme) }
    }
}

private final class SettingsWindow: NSWindow {
    var allowsKey = true
    var dismissReset: () -> Bool = { false }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if attachedSheet == nil && ((modifiers.isEmpty && event.keyCode == 53) ||
            (modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w")) {
            if !dismissReset() { close() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { if attachedSheet == nil && !dismissReset() { close() } }
    override func performClose(_ sender: Any?) { if attachedSheet == nil && !dismissReset() { close() } }
}
