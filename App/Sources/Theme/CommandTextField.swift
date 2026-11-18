import AppKit
import SwiftUI

/// 조합 중 Return은 IME에 맡기고, 확정된 입력의 명령만 화면에 전달한다.
public struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let placeholder: String
    let style: TextStyle
    let ranges: [NSRange]
    let focusToken: Int
    let submit: () -> Void
    let cancel: () -> Void
    let move: (Int) -> Void
    public init(text: Binding<String>, theme: Theme, placeholder: String, style: TextStyle = .body,
                ranges: [NSRange] = [], focusToken: Int = 0, submit: @escaping () -> Void, cancel: @escaping () -> Void,
                move: @escaping (Int) -> Void = { _ in }) {
        _text = text; self.theme = theme; self.placeholder = placeholder; self.style = style
        self.focusToken = focusToken
        self.ranges = ranges; self.submit = submit; self.cancel = cancel; self.move = move
    }
    public func makeNSView(context: Context) -> NSTextField {
        let field = CommandField()
        field.cell = PlainTextInputCell(textCell: "")
        field.isEditable = true; field.isSelectable = true
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.maximumNumberOfLines = 1; field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    public func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak field] in if let field { field.window?.makeFirstResponder(field) } }
        }
        field.font = theme.nsFont(style); field.textColor = theme.nsColor(.text)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: theme.nsColor(.text3, on: .surface3)])
        if field.stringValue != text, !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) {
            field.stringValue = text
            (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            context.coordinator.decorate(editor)
        } else if field.currentEditor() == nil {
            let value = NSMutableAttributedString(string: text, attributes: [.font: theme.nsFont(style), .foregroundColor: theme.nsColor(.text)])
            for range in ranges where NSMaxRange(range) <= value.length { value.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            field.attributedStringValue = value
        }
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
            default: return false
            }
            return true
        }
    }
}
private final class CommandField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.window === window else { return }
            window?.makeFirstResponder(self)
        } }
    }
}
