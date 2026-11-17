import AppKit
import Testing
@testable import Theme

/// `NSTextField`가 `ThinCaretFieldEditor`를 필드 편집기로 쓸 때의 얇은 커서(노트 제목 칸이 쓸 것).
@MainActor
@Suite struct ThinCaretFieldEditorTests {
    final class Delegate: NSObject, NSWindowDelegate {
        let editor: ThinCaretFieldEditor
        init(editor: ThinCaretFieldEditor) { self.editor = editor }
        func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
            client is NSTextField ? editor : nil
        }
    }

    private func makeField(_ theme: Theme) -> (NSWindow, NSTextField, ThinCaretFieldEditor, Delegate) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let field = NSTextField(string: "노트 제목")
        field.font = theme.nsFont(.title)
        field.frame = NSRect(x: 10, y: 20, width: 260, height: 20)
        window.contentView?.addSubview(field)
        let editor = ThinCaretFieldEditor(theme: theme)
        let delegate = Delegate(editor: editor)
        window.delegate = delegate
        return (window, field, editor, delegate)
    }

    @Test func fieldEditorShowsAThinCaretAtTheGlyphHeight() throws {
        let theme = try Theme.bundled()
        let (window, field, editor, delegate) = makeField(theme)
        defer { _ = delegate }
        #expect(window.makeFirstResponder(field))
        #expect(field.currentEditor() === editor)
        let caret = try #require(editor.caret)
        // 화면에 올리지 않은 창은 키 창이 아니다. 키 창일 때와 같게 본다.
        caret.forcesVisible = true
        editor.selectedRange = NSRange(location: 2, length: 0)
        #expect(caret.isActive)
        let font = try #require(field.font)
        #expect(abs(caret.frame.height - (font.ascender - font.descender)) <= 1)
        #expect(caret.frame.width <= theme.component(.caretWidth) + 0.5)
        #expect(caret.color == theme.rgba(.accent).nsColor)
        // 고른 글자가 있으면, 포커스가 없으면 보이지 않는다.
        editor.selectedRange = NSRange(location: 0, length: 2)
        #expect(!caret.isActive)
        editor.selectedRange = NSRange(location: 1, length: 0)
        #expect(caret.isActive)
        window.makeFirstResponder(nil)
        #expect(!caret.isActive)
    }

    @Test func noSystemInsertionIndicatorInTheFieldEditor() throws {
        let theme = try Theme.bundled()
        let (window, field, editor, delegate) = makeField(theme)
        defer { _ = delegate }
        window.makeFirstResponder(field)
        editor.caret?.forcesVisible = true
        editor.insertText("!", replacementRange: editor.selectedRange())
        #expect(!editor.subviews.contains { $0 is NSTextInsertionIndicator })
        #expect(!editor.shouldDrawInsertionPoint)
    }
}
