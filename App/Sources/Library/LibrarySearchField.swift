import AppKit
import SwiftUI
import Theme

/// SwiftUI의 검색 바인딩을 유지하면서 필드 편집기의 조합·자동 입력 정책을 직접 정한다.
struct LibrarySearchField: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.cell = PlainTextInputCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.placeholderString = "검색"
        field.setAccessibilityLabel("검색")
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
        field.font = theme.nsFont(.body)
        field.textColor = theme.nsColor(.text)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LibrarySearchField
        init(_ parent: LibrarySearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidEndEditing(_ notification: Notification) { controlTextDidChange(notification) }
    }
}
