import AppKit

/// 입력 칸 좌표에서 자리 글과 마지막 줄 뒤에 실제로 남는 폭.
package struct CommandLineSpace: Equatable {
    package let fieldWidth: CGFloat
    package let placeholderEnd: CGFloat
    package let lineEnd: CGFloat
    package let lineHeight: CGFloat
    package let multiline: Bool

    @MainActor init?(_ field: CommandInputField) {
        guard field.bounds.width > 0, let cell = field.cell, let font = field.font else { return nil }
        fieldWidth = field.bounds.width
        let titleRect = cell.titleRect(forBounds: field.bounds)
        let padding = field.commandEditor.textContainer?.lineFragmentPadding ?? 0
        placeholderEnd = ceil(titleRect.minX + padding + (field.placeholderAttributedString?.size().width ?? 0))
        let editor = field.currentEditor() as? NSTextView
        if (editor?.string ?? field.stringValue).isEmpty {
            lineEnd = placeholderEnd
            lineHeight = field.bounds.height
            multiline = false
            return
        }

        let manager: NSLayoutManager
        let container: NSTextContainer
        let originX: CGFloat
        let storage: NSTextStorage
        if let editor, let layout = editor.layoutManager, let textContainer = editor.textContainer, let text = editor.textStorage {
            manager = layout
            container = textContainer
            storage = text
            originX = field.convert(editor.textContainerOrigin, from: editor).x
        } else {
            manager = NSLayoutManager()
            container = NSTextContainer(size: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = padding
            container.lineBreakMode = field.lineBreakMode
            storage = NSTextStorage(attributedString: field.attributedStringValue)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            originX = titleRect.minX
        }
        let rect: CGRect = withExtendedLifetime(storage) {
            manager.ensureLayout(for: container)
            if manager.extraLineFragmentTextContainer === container { return manager.extraLineFragmentUsedRect }
            guard manager.numberOfGlyphs > 0 else { return .zero }
            return manager.lineFragmentUsedRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
        }
        lineEnd = ceil(originX + rect.maxX)
        lineHeight = rect.height > 0 ? rect.height : manager.defaultLineHeight(for: font)
        multiline = rect.minY > 0
    }
}
