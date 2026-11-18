import AppKit
import Testing
import Theme

/// 보이지 않는 창에서도 셀과 편집기의 실제 좌표를 같은 입력칸 좌표계로 비교한다.
@MainActor public enum FieldGeometry {
    public static func verifyHosted(_ view: NSView, labels: [String]) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        for label in labels {
            let field = try #require(fields(in: view).first { $0.accessibilityLabel() == label }, "입력칸 \(label)")
            try verify(field)
        }
    }

    public static func fields(in view: NSView) -> [CommandInputField] {
        if let field = view as? CommandInputField { return [field] }
        return view.subviews.flatMap { fields(in: $0) }
    }

    public static func verify(_ field: CommandInputField, begin: (() -> Void)? = nil,
                              sourceLocation: SourceLocation = #_sourceLocation) throws {
        let window = try #require(field.window, sourceLocation: sourceLocation)
        window.makeFirstResponder(nil)
        field.stringValue = ""
        window.contentView?.layoutSubtreeIfNeeded()
        let fieldOrigin = field.convert(.zero as NSPoint, to: nil)
        let baseline = field.firstBaselineOffsetFromTop
        let font = try #require(field.font, sourceLocation: sourceLocation)
        let cell = try #require(field.cell, sourceLocation: sourceLocation)
        let origin = cell.titleRect(forBounds: field.bounds).minX
        if let begin { begin() } else { window.makeFirstResponder(field) }
        let editor = try #require(field.currentEditor() as? ThinCaretFieldEditor, sourceLocation: sourceLocation)
        if let placeholder = field.placeholderAttributedString, placeholder.length > 0 {
            #expect(placeholder.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font, sourceLocation: sourceLocation)
        }
        #expect(editor.typingAttributes[.font] as? NSFont == font, sourceLocation: sourceLocation)
        func firstLine() -> NSRect {
            let rect = editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            return field.convert(window.convertFromScreen(rect), from: nil)
        }
        let caret = try #require(editor.caret)
        caret.forcesVisible = true
        defer { caret.forcesVisible = false }
        let emptyCaret = caret.frame
        let empty = firstLine()
        let sample = field.placeholderAttributedString?.string.first.map(String.init) ?? "0"
        editor.insertText(sample, replacementRange: NSRange(location: 0, length: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        caret.refresh()
        #expect(caret.isActive && caret.frame.origin == emptyCaret.origin, sourceLocation: sourceLocation)
        #expect(field.convert(.zero as NSPoint, to: nil) == fieldOrigin, sourceLocation: sourceLocation)
        let typed = firstLine()
        let scale = window.backingScaleFactor
        #expect(empty.height > 0 && empty.origin == typed.origin && (empty.height * scale).rounded() == (typed.height * scale).rounded(),
                "\(field.accessibilityLabel() ?? "") empty=\(empty) typed=\(typed)", sourceLocation: sourceLocation)
        let manager = try #require(editor.layoutManager, sourceLocation: sourceLocation)
        let container = try #require(editor.textContainer, sourceLocation: sourceLocation)
        manager.ensureLayout(for: container)
        let glyph = manager.location(forGlyphAt: 0)
        let start = field.convert(NSPoint(x: editor.textContainerOrigin.x + glyph.x,
                                          y: editor.textContainerOrigin.y + glyph.y), from: editor)
        #expect(start.y == baseline, sourceLocation: sourceLocation)
        // AppKit 셀과 필드 편집기는 같은 TextKit 줄 조각 안쪽 여백을 사용한다.
        #expect(start.x == origin + container.lineFragmentPadding, sourceLocation: sourceLocation)
    }
}
