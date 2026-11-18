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
        model.pane = pane ?? .appearance
        model.refreshCalendars()
        if window == nil {
            let panel = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                       backing: .buffered, defer: false)
            panel.allowsKey = allowsKeyWindows
            panel.isReleasedWhenClosed = false
            let view = SettingsView(model: model, theme: theme, reset: { [weak self] in self?.confirmReset() })
                .onChange(of: model.pane) { [weak self] _, _ in self?.resize() }
            panel.contentView = NSHostingView(rootView: view)
            window = panel
            resize()
            panel.center()
        }
        resize()
        if allowsKeyWindows {
            window?.makeKeyAndOrderFront(nil)
            window?.makeMain()
        }
        else { window?.orderFrontRegardless() }
    }

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

    private func resize() {
        guard let window else { return }
        window.title = "설정"
        if model.pane == .shortcuts { window.title = "단축키" }
        let wanted = theme.component(model.pane.heightToken)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame
        let available = screen.map { window.contentRect(forFrameRect: $0).height } ?? wanted
        let size = NSSize(width: theme.component(.settingsWidth), height: min(wanted, available))
        window.setContentSize(size)
    }
}

extension SettingsPane {
    var heightToken: ComponentToken {
        switch self {
        case .shortcuts: .settingsShortcutsHeight
        default: .settingsContentHeight
        }
    }
}

private final class SettingsWindow: NSWindow {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
}
