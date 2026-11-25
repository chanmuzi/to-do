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
    private var datePanel: DatePanel?
    private var preview: ReminderPreviewPanel?
    private weak var originWindow: NSWindow?
    private weak var originResponder: NSResponder?
    private var outsideClickMonitor: Any?
    public var allowsKeyWindows = true
    public var displayOptions = NoteDisplayOptions() { didSet { model?.displayOptions = displayOptions } }
    public var calendarChoices: (ScheduleItem.Kind) -> [CalendarChoice] = { _ in [] }
    public var destination: (ScheduleItem) -> ScheduleDestination? = { _ in nil }
    public private(set) var model: ReminderEditorModel?
    public var onSave: (@MainActor (NoteID, String, Bool) -> Void)?
    public private(set) var contentView: NSView?
    public init(notes: any NoteStoring, theme: Theme) { self.notes = notes; self.theme = theme }
    public func show(_ id: NoteID, anchor: NSView) throws {
        dismiss(restoringFocus: false)
        let model = try ReminderEditorModel(noteID: id, notes: notes)
        guard !model.listItems.isEmpty else { return }
        model.onSave = onSave
        model.select(nil)
        model.displayOptions = displayOptions
        model.calendarChoices = calendarChoices
        model.destination = destination
        self.model = model
        let view = NSHostingView(rootView: ReminderEditorView(model: model, theme: theme, close: { [weak self] in self?.close() }))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        contentView = view
        originWindow = anchor.window
        originResponder = anchor.window?.firstResponder
        if !allowsKeyWindows {
            let panel = ReminderPreviewPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = view
            panel.isOpaque = false
            panel.backgroundColor = .clear
            view.wantsLayer = true
            view.layer?.cornerRadius = theme.shape(.windowRadius)
            view.layer?.masksToBounds = true
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
            value.behavior = .applicationDefined
            value.delegate = self
            popover = value
            value.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        observeDismissal()
        observeDatePicker(model)
        trackSize(model)
    }

    private func observeDatePicker(_ model: ReminderEditorModel) {
        withObservationTracking {
            let state = model.datePicker
            _ = state?.choosingMonth
        } onChange: { [weak self, weak model] in
            DispatchQueue.main.async {
                guard let self, let model, self.model === model else { return }
                self.observeDatePicker(model)
            }
        }
        presentDates(model)
    }

    private func presentDates(_ model: ReminderEditorModel) {
        let state = model.datePicker
        if let state, let anchor = model.pickerAnchor, let parent = anchor.window {
            let panel: DatePanel
            if let existing = datePanel { panel = existing }
            else {
                panel = DatePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.acceptsKeys = allowsKeyWindows
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isReleasedWhenClosed = false
                panel.appearance = parent.effectiveAppearance
                panel.contentView = NSHostingView(rootView: ScheduleDatePicker(state: state, model: model, theme: theme))
                datePanel = panel
                model.pickerWindow = panel
                parent.addChildWindow(panel, ordered: .above)
            }
            let size = panel.contentView!.fittingSize
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = parent.screen?.visibleFrame ?? rect
            let x = max(screen.minX, min(rect.minX, screen.maxX - size.width))
            let y = rect.minY - size.height >= screen.minY ? rect.minY - size.height : min(rect.maxY, screen.maxY - size.height)
            panel.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
            if allowsKeyWindows { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        } else if datePanel != nil {
            closeDates()
            if allowsKeyWindows { contentView?.window?.makeKey() }
        }
    }

    private func closeDates() {
        if let panel = datePanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
            datePanel = nil
        }
    }

    private func observeDismissal() {
        let center = NotificationCenter.default
        for window in [originWindow, contentView?.window].compactMap({ $0 }) {
            center.addObserver(self, selector: #selector(windowResignedKey(_:)),
                               name: NSWindow.didResignKeyNotification, object: window)
        }
        center.addObserver(self, selector: #selector(windowBecameKey(_:)),
                           name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(focusLeft(_:)),
                           name: NSApplication.didResignActiveNotification, object: NSApp)
        if let originWindow {
            center.addObserver(self, selector: #selector(focusLeft(_:)),
                               name: NSWindow.willCloseNotification, object: originWindow)
        }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, event.window !== self.datePanel {
                if event.window !== self.contentView?.window { self.dismiss(restoringFocus: false) }
                else if self.datePanel != nil { self.model?.datePicker = nil }
            }
            return event
        }
    }

    @objc private func focusLeft(_ notification: Notification) { dismiss(restoringFocus: false) }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window !== datePanel, window !== originWindow, window !== contentView?.window else { return }
        dismiss(restoringFocus: false)
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        // AppKit은 새 키 창을 지정하기 전에 이전 키 창의 알림을 보낸다.
        DispatchQueue.main.async { [weak self, weak model] in
            guard let self, let model, self.model === model else { return }
            if NSApp.keyWindow != nil && (NSApp.keyWindow === self.datePanel || NSApp.keyWindow === self.contentView?.window) { return }
            self.dismiss(restoringFocus: false)
        }
    }

    private func trackSize(_ model: ReminderEditorModel) {
        withObservationTracking {
            _ = model.listItems; _ = model.selectedID; _ = model.error
        } onChange: { [weak self, weak model] in
            DispatchQueue.main.async {
                guard let self, let model, self.model === model, let view = self.contentView else { return }
                guard !model.listItems.isEmpty else { self.close(); return }
                let size = view.fittingSize
                self.popover?.contentSize = size
                self.preview?.setContentSize(size)
                self.trackSize(model)
            }
        }
    }
    public func close() { dismiss(restoringFocus: true) }

    private func finishComposition() {
        if let editor = contentView?.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            editor.unmarkText()
        }
    }

    private func dismiss(restoringFocus: Bool) {
        guard model != nil else { return }
        finishComposition()
        let window = originWindow
        let responder = originResponder
        let value = popover
        let panel = preview
        clearPresentation()
        value?.delegate = nil
        value?.close()
        panel?.orderOut(nil)
        if restoringFocus, allowsKeyWindows, let responder { window?.makeFirstResponder(responder) }
    }

    public func popoverWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSPopover, closing === popover { finishComposition() }
    }

    public func popoverDidClose(_ notification: Notification) {
        guard let closing = notification.object as? NSPopover, closing === popover else { return }
        clearPresentation()
    }

    private func clearPresentation() {
        NotificationCenter.default.removeObserver(self)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        closeDates()
        outsideClickMonitor = nil
        popover = nil
        preview = nil
        contentView = nil
        model = nil
        originWindow = nil
        originResponder = nil
    }

    isolated deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }
}
private final class ReminderPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DatePanel: NSPanel {
    var acceptsKeys = true
    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }
}
