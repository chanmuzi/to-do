import AppKit
import SwiftUI
import Models

/// 보이는 줄과 같은 틀에서 입력을 받는다. 첫 누름부터 이 줄이 응답자를 소유하므로
/// SwiftUI의 첫 toolbar 버튼으로 키보드 포커스가 넘어가지 않는다.
struct LibraryRowInput: NSViewRepresentable {
    let model: LibraryModel
    let note: Note
    let label: String
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> LibraryRowInputView { LibraryRowInputView() }
    func updateNSView(_ view: LibraryRowInputView, context: Context) {
        view.model = model
        view.note = note
        view.hover = hover
        view.setAccessibilityLabel(label)
        view.setAccessibilityValue(model.selectedNoteID == note.id ? "선택됨" : "")
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: model.index.trash.contains { $0.id == note.id } ? "복원 후 열기" : "열기") {
                model.open(note)
                return true
            }
        ])
    }
}

final class LibraryRowInputView: NSView {
    var model: LibraryModel?
    var note: Note?
    var hover: (Bool) -> Void = { _ in }
    private var tracking: NSTrackingArea?
    private var pressed = false
    private var clickCount = 1

    init() {
        super.init(frame: .zero)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
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
        !isHidden && frame.contains(point) ? self : nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
    override func mouseDown(with event: NSEvent) {
        pressed = true
        clickCount = event.clickCount
        window?.makeFirstResponder(self)
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)), let note else { return }
        model?.activate(note, clickCount: clickCount)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: model?.openSelected()
        case 125: model?.moveSelection(by: 1)
        case 126: model?.moveSelection(by: -1)
        case 49: if let note { model?.activate(note) }
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard let model, let note else { return false }
        model.activate(note)
        window?.makeFirstResponder(self)
        return true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let note else { return nil }
        model.activate(note)
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        let trash = model.index.trash.contains { $0.id == note.id }
        let open = NSMenuItem(title: trash ? "되돌리기" : "열기", action: #selector(openNote), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if !trash {
            let move = NSMenuItem(title: "스페이스 옮기기", action: #selector(moveNote), keyEquivalent: "")
            move.target = self
            menu.addItem(move)
        }
        return menu
    }
    @objc private func openNote() { if let note { model?.open(note) } }
    @objc private func moveNote() { if let note { model?.router.route(.openSpacePicker(note.id)) } }
}

struct LibrarySelectableRow<Content: View>: View {
    let model: LibraryModel
    let note: Note
    let label: String
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
            }
            .overlay { LibraryRowInput(model: model, note: note, label: label) { hovered = $0 } }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : model.theme.motion.animation, value: hovered)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : model.theme.motion.animation, value: model.selectedNoteID)
    }
}
