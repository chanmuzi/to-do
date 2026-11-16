import AppKit

/// 편집기의 텍스트 뷰. 키와 마우스를 받아 `MarkdownEditor`에 넘기는 일만 한다.
final class EditorTextView: NSTextView {
    weak var editor: EditorController?
    /// 본문 안쪽 여백의 왼쪽 위(위와 아래 여백이 달라 직접 정한다).
    var containerOrigin: NSPoint = .zero
    var caretWidth: CGFloat = 1

    override var textContainerOrigin: NSPoint { containerOrigin }

    // MARK: 커서

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var thin = rect
        thin.size.width = caretWidth
        super.drawInsertionPoint(in: thin, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        // 커서를 지울 때 원래 너비만큼만 다시 그리면 잔상이 남을 수 있어 조금 넓힌다.
        super.setNeedsDisplay(rect.insetBy(dx: -caretWidth, dy: 0), avoidAdditionalLayout: flag)
    }

    // MARK: 포커스

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.focusDidChange() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { editor?.focusDidChange() }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        editor?.windowDidChange()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { editor?.widthDidChange() }
    }

    // MARK: 키

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, !hasMarkedText(),
           let action = EditorShortcuts.action(keyCode: event.keyCode, modifiers: Self.modifiers(of: event)) {
            editor?.perform(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func modifiers(of event: NSEvent) -> EditorShortcuts.Modifiers {
        let flags = event.modifierFlags
        var result: EditorShortcuts.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    // MARK: 한글 조합

    // 조합 중인 글자는 원문에 들어가지만 `textDidChange`가 오지 않는다. 그 글자까지 저장되고
    // 조합 중에 줄이 넘어가도 창 높이가 따라가도록 곧바로 알린다.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        editor?.flushPendingChange()
    }

    override func unmarkText() {
        super.unmarkText()
        editor?.flushPendingChange()
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        if editor?.handleMouseDown(at: convert(event.locationInWindow, from: nil)) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // 누를 수 있는 곳(체크박스, 꺾쇠, 링크) 위에서는 화살표, 글자 위에서만 I자 커서(규칙 9).
        if editor?.handleMouseMoved(at: convert(event.locationInWindow, from: nil)) == true {
            NSCursor.arrow.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if editor?.isInteractive(at: convert(event.locationInWindow, from: nil)) == true {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        editor?.handleMouseExited()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["editor"] != nil {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["editor": true]
        ))
    }

    // MARK: 복사, 붙여넣기

    override func copy(_ sender: Any?) {
        guard let editor else { return super.copy(sender) }
        editor.copySelection(to: .general)
    }

    override func cut(_ sender: Any?) {
        guard let editor, isEditable else { return super.cut(sender) }
        guard editor.copySelection(to: .general) else { return }
        insertText("", replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) {
        guard let editor, isEditable else { return super.paste(sender) }
        editor.paste(from: .general)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }
}
