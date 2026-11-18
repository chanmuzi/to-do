import AppKit

/// CommandTextField와 AppKit 화면이 함께 쓰는 한 줄 입력칸.
@MainActor
open class CommandInputField: NSTextField {
    public let commandEditor: ThinCaretFieldEditor

    public init(theme: Theme, editor: ThinCaretFieldEditor? = nil) {
        commandEditor = editor ?? ThinCaretFieldEditor(theme: theme)
        super.init(frame: .zero)
        cell = PlainTextInputCell(textCell: "")
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = false
        maximumNumberOfLines = 1
        cell?.isScrollable = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

    open override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if let font, let layout = commandEditor.layoutManager {
            size.height = max(size.height, ceil(layout.defaultLineHeight(for: font)))
        }
        return size
    }

    public func apply(font: NSFont, ink: NSColor, placeholder: String = "", placeholderInk: NSColor) {
        self.font = font
        textColor = ink
        placeholderAttributedString = NSAttributedString(string: placeholder,
            attributes: [.font: font, .foregroundColor: placeholderInk])
    }
}
