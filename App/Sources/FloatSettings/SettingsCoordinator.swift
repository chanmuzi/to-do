import AppKit
import SwiftUI
import Theme

package final class SettingsCoordinator {
    package let model: SettingsModel
    private let theme: Theme
    package var allowsKeyWindows = true
    package private(set) var window: NSWindow?

    package init(model: SettingsModel, theme: Theme) {
        self.model = model
        self.theme = theme
    }

    package func show(_ pane: SettingsPane? = nil) {
        if let pane { model.pane = pane }
        model.refreshCalendars()
        if window == nil {
            let panel = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                       backing: .buffered, defer: false)
            panel.allowsKey = allowsKeyWindows
            panel.isReleasedWhenClosed = false
            let view = SettingsView(model: model, theme: theme)
                .onChange(of: model.pane) { [weak self] _, _ in self?.resize() }
            panel.contentView = NSHostingView(rootView: view)
            window = panel
            resize()
            panel.center()
        }
        resize()
        if allowsKeyWindows { window?.makeKeyAndOrderFront(nil) }
        else { window?.orderFrontRegardless() }
    }

    private func resize() {
        guard let window else { return }
        window.title = model.pane.rawValue + " 설정"
        if model.pane == .shortcuts { window.title = "단축키" }
        let size = NSSize(width: theme.component(.settingsWidth),
                          height: theme.component(model.pane.heightToken))
        window.setContentSize(size)
    }
}

extension SettingsPane {
    var heightToken: ComponentToken {
        switch self {
        case .shortcuts: .settingsShortcutsHeight
        case .schedule: .settingsScheduleHeight
        case .app: .settingsAppHeight
        case .editor, .appearance: .settingsPaneHeight
        }
    }
}

private final class SettingsWindow: NSWindow {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
}
