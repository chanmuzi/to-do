import AppKit
import SwiftUI
import Models
import Theme

/// 보이는 줄과 같은 틀에서 입력을 받는다. 첫 누름부터 이 줄이 응답자를 소유하므로
/// SwiftUI의 첫 toolbar 버튼으로 키보드 포커스가 넘어가지 않는다.
struct LibraryRowInput: NSViewRepresentable {
    let model: LibraryModel
    let note: Note
    let label: String
    let isUpcoming: Bool
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> LibraryRowInputView { LibraryRowInputView() }
    func updateNSView(_ view: LibraryRowInputView, context: Context) {
        view.model = model
        view.note = note
        view.isUpcoming = isUpcoming
        view.hover = hover
        view.setAccessibilityLabel(label)
        view.setAccessibilityValue(model.selectedNoteID == note.id ? "선택됨" : "")
        view.configureActions()
        var actions = [NSAccessibilityCustomAction(name: view.restoresTrash ? "복원 후 열기" : "열기") { [weak view] in
            view?.openNote()
            return view != nil
        }]
        if model.allowsRowPin {
            actions.append(NSAccessibilityCustomAction(name: view.pin.accessibilityLabel() ?? "") { [weak view] in
                view?.togglePin()
                return view != nil
            })
        }
        actions.append(NSAccessibilityCustomAction(name: "더 보기") { [weak view] in
            view?.showMenu()
            return view != nil
        })
        view.setAccessibilityCustomActions(actions)
    }
}

final class LibraryRowInputView: NSView {
    var model: LibraryModel?
    var note: Note?
    var isUpcoming = false
    var hover: (Bool) -> Void = { _ in }
    let pin = LibraryRowActionButton()
    let more = LibraryRowActionButton()
    private var popup: NSPanel?
    private var pointer: NSPoint?
    private var lastReveal = false
    private var pinned = false
    private var allowsPin = false
    private var pressed = false
    private var clickCount = 1

    init() {
        super.init(frame: .zero)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addSubview(pin)
        addSubview(more)
        pin.target = self
        pin.action = #selector(togglePin)
        more.target = self
        more.action = #selector(showMenu)
        more.setAccessibilityLabel("더 보기")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("코드로만 만든다") }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let note { model?.activate(note) }
        return accepted
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        return more.hitTest(local) ?? pin.hitTest(local) ?? self
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    func configureActions() {
        guard let model, let note else { return }
        let theme = model.theme
        allowsPin = model.allowsRowPin
        pinned = model.index.windows[note.id]?.isPinned == true
        pin.setAccessibilityLabel(pinned ? "고정 해제" : "고정")
        pin.image = theme.symbolImage(pinned ? "pin.fill" : "pin", size: .iconMedium)
        more.image = theme.symbolImage("ellipsis", size: .iconMedium)
        for button in [pin, more] {
            button.radius = theme.shape(.controlRadius)
            button.hoverColor = theme.nsColor(.hover)
        }
        updateActions()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // 스크롤하거나 구획이 바뀌면 포인터를 움직이지 않아도 새 줄의 좌표로 다시 잰다.
        synchronizeHover(at: window?.mouseLocationOutsideOfEventStream)
    }

    func synchronizeHover(at windowPoint: NSPoint?, forceUpdate: Bool = false) {
        let local = windowPoint.map { convert($0, from: nil) }
            .flatMap { bounds.contains($0) && visibleRect.contains($0) ? $0 : nil }
        guard local != pointer || forceUpdate else { return }
        pointer = local
        updateActions()
    }
    override func mouseEntered(with event: NSEvent) { synchronizeHover(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { synchronizeHover(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { synchronizeHover(at: nil) }

    override func layout() {
        super.layout()
        updateActions()
    }

    private func updateActions() {
        guard let model, let note else { return }
        let theme = model.theme
        var inside = pointer != nil
        #if DEBUG
        if let preview = model.previewNoteHover { inside = preview == note.id }
        #endif
        let revealed = inside || popup?.isVisible == true
        let frames = LibraryRowActionLayout(theme: theme, allowsPin: allowsPin).frames(in: bounds, revealed: revealed)
        pin.frame = frames.pin
        more.frame = frames.more
        pin.isHidden = !allowsPin || !(revealed || pinned)
        more.isHidden = !revealed
        for button in [pin, more] {
            button.showsHover = revealed && (pointer.map(button.frame.contains) == true || (button === more && popup?.isVisible == true))
            let ink: ColorToken = button.showsHover ? .text : revealed ? .text2 : .text3
            button.contentTintColor = theme.nsColor(ink == .text3 && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .text2 : ink)
        }
        if lastReveal != revealed {
            lastReveal = revealed
            // AppKit 배치 중 SwiftUI 상태를 바꾸지 않는다.
            DispatchQueue.main.async { [weak self] in
                guard let self, lastReveal == revealed else { return }
                hover(revealed)
            }
        }
    }

    @objc func togglePin() {
        guard let note, let model, allowsPin else { return }
        window?.makeFirstResponder(self)
        let host = window
        model.togglePin(note)
        DispatchQueue.main.async { [weak host] in
            guard let host, let root = host.contentView else { return }
            root.layoutSubtreeIfNeeded()
            let rows = root.libraryNoteRows
            if model.selectedNoteID == note.id, let moved = rows.first(where: { $0.note?.id == note.id }) {
                host.makeFirstResponder(moved)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(); return }
        pressed = true
        clickCount = event.clickCount
        window?.makeFirstResponder(self)
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)), let note else { return }
        if isUpcoming {
            if clickCount == 1 { openNote() }
        } else {
            model?.activate(note, clickCount: clickCount)
        }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            if isUpcoming { openNote() } else { model?.openSelected() }
        case 125: model?.moveSelection(by: 1)
        case 126: model?.moveSelection(by: -1)
        case 49: if let note { model?.activate(note) }
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard let model, let note else { return false }
        window?.makeFirstResponder(self)
        if isUpcoming { openNote() } else { model.activate(note) }
        return true
    }
    override func rightMouseDown(with event: NSEvent) { showMenu() }

    @objc func showMenu() {
        guard let model, let note, let menu = noteMenu() else { return }
        model.activate(note)
        window?.makeFirstResponder(self)
        popup?.close()
        guard let panel = SettingsValueMenu(menu: menu, anchor: more, offset: CGSize(width: 0, height: model.theme.space(.sp1))) else { return }
        popup = panel
        NotificationCenter.default.addObserver(self, selector: #selector(menuClosing), name: NSWindow.willCloseNotification, object: panel)
        updateActions()
    }
    @objc private func menuClosing() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: popup)
        popup = nil
        synchronizeHover(at: window?.mouseLocationOutsideOfEventStream, forceUpdate: true)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { popup?.close() }
    }
    func noteMenu() -> NSMenu? {
        guard let model, let note else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let theme = model.theme
        func add(_ title: String, _ symbol: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            let image = theme.symbolImage(symbol, size: .menuIcon)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [theme.nsColor(.text2)]))
            item.view = PickerMenuRow(theme: theme, text: title, dot: image, selected: false,
                                      width: theme.component(.menuWidth), command: true)
        }
        add(restoresTrash ? "되돌리기" : "열기", restoresTrash ? "arrow.uturn.backward" : "macwindow", #selector(openNote))
        if !restoresTrash {
            add(note.isArchived ? "되돌리기" : "보관함으로", "archivebox", #selector(toggleArchive))
            add("스페이스 옮기기", "briefcase", #selector(moveNote))
        }
        return menu
    }
    @objc private func toggleArchive() { if let note { model?.toggleArchive(note) } }
    fileprivate var restoresTrash: Bool {
        guard !isUpcoming, let note, let model else { return false }
        return model.index.trash.contains { $0.id == note.id }
    }

    @objc fileprivate func openNote() {
        guard let model, let note else { return }
        if isUpcoming { model.router.route(.openNote(note.id)) } else { model.open(note) }
    }
    @objc private func moveNote() { if let note { model?.router.route(.openSpacePicker(note.id)) } }
}

extension NSView {
    var libraryNoteRows: [LibraryRowInputView] {
        if let row = self as? LibraryRowInputView { return [row] }
        return subviews.flatMap(\.libraryNoteRows)
    }
    func libraryNoteRow(_ id: NoteID) -> LibraryRowInputView? {
        libraryNoteRows.first { $0.note?.id == id }
    }
}

struct LibrarySelectableRow<Content: View>: View {
    let model: LibraryModel
    let note: Note
    let label: String
    var isUpcoming = false
    var highlightInsets = EdgeInsets()
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        content().accessibilityHidden(true)
            .background {
                let selected = model.selectedNoteID == note.id
                RoundedRectangle(cornerRadius: model.theme.shape(.controlRadius))
                    .fill(selected ? model.theme.libraryColor(.selected) : hovered ? model.theme.libraryColor(.hover) : .clear)
                    .padding(highlightInsets)
                    .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : model.theme.motion.animation, value: hovered)
                    .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : model.theme.motion.animation, value: selected)
            }
            .overlay { LibraryRowInput(model: model, note: note, label: label, isUpcoming: isUpcoming) { hovered = $0 } }
    }
}
