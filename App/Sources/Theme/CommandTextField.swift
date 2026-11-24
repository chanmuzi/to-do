import AppKit
import SwiftUI

/// 조합 중 Return은 IME에 맡기고, 확정된 입력의 명령만 화면에 전달한다.
public struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let placeholder: String
    let font: NSFont
    let ranges: [NSRange]
    private var reportLineSpace: ((CommandLineSpace) -> Void)?
    let wraps: Bool
    let focusToken: Int
    let submit: () -> Void
    let cancel: () -> Void
    let move: (Int) -> Void
    let moveDay: ((Int) -> Void)?
    let tab: ((Bool) -> Void)?
    public init(text: Binding<String>, theme: Theme, placeholder: String, style: TextStyle = .body, font: NSFont? = nil,
                ranges: [NSRange] = [], focusToken: Int = 0, wraps: Bool = false, submit: @escaping () -> Void, cancel: @escaping () -> Void,
                move: @escaping (Int) -> Void = { _ in }, moveDay: ((Int) -> Void)? = nil, tab: ((Bool) -> Void)? = nil) {
        _text = text; self.theme = theme; self.placeholder = placeholder; self.font = font ?? theme.nsFont(style)
        self.moveDay = moveDay
        self.tab = tab
        self.focusToken = focusToken
        self.wraps = wraps
        self.ranges = ranges; self.submit = submit; self.cancel = cancel; self.move = move
    }
    package func onLineSpaceChange(_ action: @escaping (CommandLineSpace) -> Void) -> Self {
        var field = self
        field.reportLineSpace = action
        return field
    }

    public func makeNSView(context: Context) -> CommandInputField {
        let field = CommandField(theme: theme)
        if wraps {
            field.maximumNumberOfLines = 0
            field.cell?.isScrollable = false
            field.cell?.wraps = true
            field.lineBreakMode = .byWordWrapping
        }
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    public func updateNSView(_ field: CommandInputField, context: Context) {
        context.coordinator.parent = self
        if let field = field as? CommandField {
            field.reportLineSpace = reportLineSpace
            field.scheduleMeasurement()
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak field] in if let field { field.window?.makeFirstResponder(field) } }
        }
        field.apply(font: font, ink: theme.nsColor(.text), placeholder: placeholder,
                    placeholderInk: theme.nsColor(.text3, on: .surface3))
        if field.stringValue != text, !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) {
            field.stringValue = text
            (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            context.coordinator.decorate(editor)
        } else if field.currentEditor() == nil {
            let value = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.nsColor(.text)])
            for range in ranges where NSMaxRange(range) <= value.length { value.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            field.attributedStringValue = value
        }
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView field: CommandInputField, context: Context) -> CGSize? {
        guard wraps, let width = proposal.width, width.isFinite, width > 0,
              let cell = field.cell else { return nil }
        let size = cell.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(field.intrinsicContentSize.height, ceil(size.height)))
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor public final class Coordinator: NSObject, NSTextFieldDelegate {
        var focusToken: Int?
        var parent: CommandTextField
        init(_ parent: CommandTextField) { self.parent = parent }
        func decorate(_ editor: NSTextView) {
            guard !editor.hasMarkedText(), let layout = editor.layoutManager else { return }
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: NSRange(location: 0, length: (editor.string as NSString).length))
            for range in parent.ranges where NSMaxRange(range) <= (editor.string as NSString).length {
                layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
            }
        }
        public func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let editor = field?.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                self?.decorate(editor)
            }
        }
        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            parent.text = field.stringValue
        }
        public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)):
                guard parent.text.isEmpty, let moveDay = parent.moveDay else { return false }
                moveDay(selector == #selector(NSResponder.moveLeft(_:)) ? -1 : 1)
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                guard let tab = parent.tab else { return false }
                tab(selector == #selector(NSResponder.insertBacktab(_:)))
            default: return false
            }
            return true
        }
    }
}
private final class CommandField: CommandInputField {
    var reportLineSpace: ((CommandLineSpace) -> Void)?
    private var measurementPending = false
    private var lastSpace: CommandLineSpace?

    func scheduleMeasurement() {
        guard reportLineSpace != nil, !measurementPending else { return }
        measurementPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            measurementPending = false
            guard let space = CommandLineSpace(self), space != lastSpace else { return }
            lastSpace = space
            reportLineSpace?(space)
        }
    }
    override func layout() {
        super.layout()
        scheduleMeasurement()
    }
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        scheduleMeasurement()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.window === window else { return }
            window?.makeFirstResponder(self)
        } }
    }
}
