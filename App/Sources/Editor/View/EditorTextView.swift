import AppKit

/// 편집기의 텍스트 뷰. 키와 마우스를 받아 `MarkdownEditor`에 넘기는 일만 한다.
final class EditorTextView: NSTextView {
    weak var editor: EditorController?
    /// 본문 안쪽 여백의 왼쪽 위(위와 아래 여백이 달라 직접 정한다).
    var containerOrigin: NSPoint = .zero

    override var textContainerOrigin: NSPoint { containerOrigin }

    // 입력 커서는 시스템의 것을 그대로 쓰고 색만 `insertionPointColor`로 맞춘다. 지금 macOS의 커서는
    // 텍스트 뷰가 그리는 것이 아니라 따로 놓이는 표시 뷰여서, 옛 그리기 경로(`drawInsertionPoint`)를
    // 덮어써 너비를 줄이면 두 번째 커서가 그려지고 지워지지 않는 자국이 남는다(D-025).

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

    /// 편집 단축키는 이 편집기에서 글을 쓰는 중일 때만 받는다: 본문에 포커스가 있고 창이 키 창이다.
    /// 키 창이 아닌 창의 뷰에도 `performKeyEquivalent`가 올 수 있다(다른 창이 넘긴 키, 창을 가리지 않고
    /// 부르는 쪽). 그때 받으면 사용자가 보고 있지 않은 노트의 글이 바뀐다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if editor?.isActive == true, !hasMarkedText(),
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
        var replacement = replacementRange
        // 조합을 시작하기 전에 자리를 만든다(고른 글자를 기호와 함께 지우고, 정해 둔 서식의 기호를 넣는다).
        // 조합이 시작된 뒤에는 원문을 따로 고치지 않는다.
        if !hasMarkedText(), let editor,
           replacementRange.location == NSNotFound || replacementRange == self.selectedRange() {
            editor.prepareForComposition()
            replacement = NSRange(location: NSNotFound, length: 0)
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacement)
        editor?.flushPendingChange()
        editor?.compositionDidChange()
    }

    override func unmarkText() {
        super.unmarkText()
        editor?.flushPendingChange()
        editor?.compositionDidChange()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        editor?.compositionDidChange()
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        if editor?.handleMouseDown(at: convert(event.locationInWindow, from: nil)) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // 이 뷰 위에 겹쳐 뜬 다른 뷰(노트 창의 휴지통, 닫기)가 마우스를 받는 자리에서는 글자 칸이 아니다.
        // I자 커서를 넣지 않고 화살표로 둔다(규칙 9).
        guard isHitView(for: event) else {
            editor?.handleMouseExited()
            NSCursor.arrow.set()
            return
        }
        // 누를 수 있는 곳(체크박스, 꺾쇠, 링크) 위에서는 화살표, 글자 위에서만 I자 커서(규칙 9).
        if editor?.handleMouseMoved(at: convert(event.locationInWindow, from: nil)) == true {
            NSCursor.arrow.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    /// 그 자리에서 마우스를 받는 뷰가 이 뷰(또는 그 안의 뷰)인지.
    func isHitView(for event: NSEvent) -> Bool {
        guard let root = window?.contentView else { return true }
        // `hitTest`는 받는 뷰의 상위 뷰 좌표로 받는다.
        let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        guard let hit = root.hitTest(point) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isHitView(for: event) else {
            NSCursor.arrow.set()
            return
        }
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
