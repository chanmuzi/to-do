import AppKit

/// 얇은 커서(`TextCaret`)를 쓰는 필드 편집기. `NSTextField`가 글을 고칠 때 쓰는 텍스트 뷰를 이것으로 바꾼다.
///
/// 창의 대리자에서 넘긴다(칸마다 하나씩 만들지 않고 창이 하나를 들고 돌려 쓴다):
///
/// ```swift
/// private lazy var titleEditor = ThinCaretFieldEditor(theme: theme)
///
/// func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
///     client is TitleField ? titleEditor : nil
/// }
/// ```
///
/// 시스템의 커서 표시(`NSTextInsertionIndicator`)는 만들지 않는다. `insertionPointColor`를 따로 정할
/// 필요도 없다(색은 `accent`, 너비는 `caret-w`).
@MainActor
open class ThinCaretFieldEditor: NSTextView {
    public private(set) var caret: TextCaret?

    public convenience init(theme: Theme) {
        self.init(frame: .zero)
        isFieldEditor = true
        isRichText = false
        drawsBackground = false
        caret = TextCaret(textView: self, theme: theme)
    }

    open override var shouldDrawInsertionPoint: Bool { false }

    open override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        caret?.refresh(focused: accepted ? true : nil)
        return accepted
    }

    open override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        caret?.refresh(focused: accepted ? false : nil)
        return accepted
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        caret?.refresh()
    }

    open override func layout() {
        super.layout()
        caret?.reposition()
    }

    open override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        caret?.refresh()
    }

    open override func unmarkText() {
        super.unmarkText()
        caret?.refresh()
    }
}
