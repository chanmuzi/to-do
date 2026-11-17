import AppKit
import SwiftUI
import Observation
import Models
import Store
import Theme

public final class ReminderEditorCoordinator: NSObject, NSPopoverDelegate {
    private let notes: any NoteStoring
    private let theme: Theme
    private var popover: NSPopover?
    private var preview: ReminderPreviewPanel?
    private weak var originWindow: NSWindow?
    private weak var originResponder: NSResponder?
    public var allowsKeyWindows = true
    public var onSave: (@MainActor (NoteID, String, Bool) -> Void)?
    public private(set) var contentView: NSView?
    public init(notes: any NoteStoring, theme: Theme) { self.notes = notes; self.theme = theme }
    public func show(_ id: NoteID, anchor: NSView) throws {
        close()
        let model = try ReminderEditorModel(noteID: id, notes: notes)
        model.onSave = onSave
        let view = NSHostingView(rootView: ReminderEditorView(model: model, theme: theme, close: { [weak self] in self?.close() }))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        contentView = view
        originWindow = anchor.window
        originResponder = anchor.window?.firstResponder
        if !allowsKeyWindows {
            let panel = ReminderPreviewPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = view
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            if let window = anchor.window {
                panel.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY - size.height))
            }
            panel.orderFrontRegardless()
            preview = panel
        } else {
            let value = NSPopover()
            value.contentViewController = NSViewController()
            value.contentViewController?.view = view
            value.contentSize = size
            value.behavior = .transient
            value.delegate = self
            popover = value
            value.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }
    public func close() {
        popover?.close(); popover = nil
        preview?.orderOut(nil); preview = nil; contentView = nil
        restoreFocus()
    }
    public func popoverDidClose(_ notification: Notification) { restoreFocus() }
    private func restoreFocus() {
        if allowsKeyWindows, let originResponder { originWindow?.makeFirstResponder(originResponder) }
        originWindow = nil; originResponder = nil
    }
}
private final class ReminderPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

