import AppKit
import Theme

/// 편집기의 텍스트 뷰. 키와 마우스를 받아 `MarkdownEditor`에 넘기는 일만 한다.
final class EditorTextView: PlainTextInputView {
    private(set) var selectingWithMouse = false
    weak var editor: EditorController?
    /// 본문 안쪽 여백의 왼쪽 위(위와 아래 여백이 달라 직접 정한다).
    var containerOrigin: NSPoint = .zero

    override var textContainerOrigin: NSPoint { containerOrigin }

    /// 얇은 입력 커서. 시스템의 커서 표시(`NSTextInsertionIndicator`)는 줄 높이 전체를 덮고 너비를 정할 수
    /// 없어 만들지 않게 하고(`shouldDrawInsertionPoint`), 이 뷰 위에 따로 올린 작은 뷰가 대신한다(D-042).
    var caret: TextCaret?

    override var shouldDrawInsertionPoint: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        editor?.drawBlockColors(in: dirtyRect)
        if let manager = textLayoutManager, let context = NSGraphicsContext.current?.cgContext {
            let origin = textContainerOrigin
            let start = manager.textViewportLayoutController.viewportRange?.location
            manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
                guard frame.minY <= dirtyRect.maxY else { return false }
                if frame.maxY >= dirtyRect.minY, let paragraph = fragment as? MarkdownLayoutFragment {
                    paragraph.drawBackground(at: frame.origin, in: context)
                }
                return true
            }
        }
        editor?.drawBlockSelection(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        editor?.layoutScheduleButtons()
        caret?.reposition()
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if let target = editor?.caretScrollTarget(for: range) {
            scrollToVisible(target)
        } else {
            super.scrollRangeToVisible(range)
        }
    }

    // MARK: 되돌리기

    /// 되돌리기 기록은 편집기가 직접 든다. 편집 메뉴와 ⌘Z가 창의 기록이 아니라 이것을 쓰게 한다.
    override var undoManager: UndoManager? { editor?.editorUndoManager ?? super.undoManager }

    @objc func undo(_ sender: Any?) {
        editor?.editorUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        editor?.editorUndoManager.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(editMarkdownLink(_:)) {
            let target = editor?.currentLinkTarget
            let menuItem = item as? NSMenuItem
            if case .existing = target { menuItem?.title = "링크 고치기" } else { menuItem?.title = "링크 추가" }
            menuItem?.toolTip = target == nil ? editor?.linkSelectionHelp : nil
            return isEditable && !hasMarkedText() && editor?.isActive == true && target != nil
        }
        return switch item.action {
        case #selector(undo(_:)): editor?.editorUndoManager.canUndo ?? false
        case #selector(redo(_:)): editor?.editorUndoManager.canRedo ?? false
        case #selector(copy(_:)) where editor?.blockSelection != nil: true
        case #selector(cut(_:)) where editor?.blockSelection != nil: isEditable
        case #selector(pasteInsideBlock(_:)): isEditable && editor?.blockSelection != nil && !hasMarkedText()
        case #selector(insertMarkdownDivider(_:)): isEditable && editor?.isActive == true && !hasMarkedText()
        case #selector(duplicateMarkdownBlock(_:)): isEditable && editor?.isActive == true
        default: super.validateUserInterfaceItem(item)
        }
    }

    // MARK: 포커스

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.focusDidChange() }
        caret?.refresh(focused: accepted ? true : nil)
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { editor?.focusDidChange() }
        caret?.refresh(focused: accepted ? false : nil)
        return accepted
    }

    /// 텍스트 뷰가 조합을 끝내는 동안에는 조합 중인 글자가 잠깐 비어 보인다(지웠다가 다시 넣는다). 그 사이에
    /// 편집기가 "조합이 글자 없이 끝났다"로 보고 기호를 치우거나 중간 원문을 알리지 않게 한다.
    private func endingComposition<T>(_ body: () -> T) -> T {
        let wasEnding = editor?.isEndingComposition ?? false
        editor?.isEndingComposition = true
        defer { editor?.isEndingComposition = wasEnding }
        return body()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        editor?.windowDidChange()
        caret?.refresh()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { editor?.widthDidChange(); window?.invalidateCursorRects(for: self) }
    }

    // MARK: 키

    /// 편집 단축키는 이 편집기에서 글을 쓰는 중일 때만 받는다: 본문에 포커스가 있고 창이 키 창이다.
    /// 키 창이 아닌 창의 뷰에도 `performKeyEquivalent`가 올 수 있다(다른 창이 넘긴 키, 창을 가리지 않고
    /// 부르는 쪽). 그때 받으면 사용자가 보고 있지 않은 노트의 글이 바뀐다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if editor?.isActive == true,
           let action = EditorShortcuts.action(keyCode: event.keyCode, modifiers: Self.modifiers(of: event)),
           action != .pasteInside || editor?.blockSelection != nil,
           action == .bold || !hasMarkedText() {
            editor?.perform(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = Self.modifiers(of: event)
        if event.keyCode == EditorShortcuts.Key.returnKey, !hasMarkedText(),
           modifiers == .shift || modifiers == .control {
            doCommand(by: #selector(NSResponder.insertLineBreak(_:)))
            return
        }
        // 입력기가 조합을 시작하기 전 한 키를 소비한다.
        if editor?.blockSelection != nil, modifiers.intersection([.command, .control]).isEmpty,
           let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
            _ = editor?.dismissBlocks()
            return
        }
        super.keyDown(with: event)
    }

    override func selectAll(_ sender: Any?) {
        editor?.clearBlocks()
        super.selectAll(sender)
    }

    @objc func insertMarkdownDivider(_ sender: Any?) {
        guard isEditable, editor?.isActive == true, !hasMarkedText() else { return }
        editor?.insertDivider()
    }

    @objc func duplicateMarkdownBlock(_ sender: Any?) {
        guard editor?.isActive == true else { return }
        editor?.perform(.duplicate)
    }

    @objc func pasteInsideBlock(_ sender: Any?) {
        guard isEditable, editor?.blockSelection != nil else { return }
        editor?.paste(from: .general, inside: true)
    }

    override func accessibilityValueDescription() -> String? {
        if let editor, let selection = editor.blockSelection, selection.rows.count == 1,
           editor.document.lines[selection.focus].kind == .divider { return "구분선" }
        return editor?.selectedInk?.label ?? super.accessibilityValueDescription()
    }

    @objc func editMarkdownLink(_ sender: Any?) {
        guard editor?.isActive == true else { return }
        editor?.beginLinkEditing()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let blocks = editor?.blockSelection
        let selection = selectedRange()
        window?.makeFirstResponder(self)
        let menu = super.menu(for: event)?.copy() as? NSMenu ?? NSMenu()
        if let blocks { editor?.showBlocks(blocks) }
        else if selection.length > 0 { setSelectedRange(selection) }
        if let editor, blocks == nil, selection.length == 0, case .link(let line, let offset, _) = editor.hit(at: convert(event.locationInWindow, from: nil)),
           let span = editor.document.lines[line].markedSpans.first(where: { $0.range.location == editor.document.lines[line].start + offset }) {
            setSelectedRange(span.contentRange)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let item = menu.addItem(withTitle: "링크 추가", action: #selector(editMarkdownLink(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = validateUserInterfaceItem(item)
        if let editor {
            let ink = menu.addItem(withTitle: "색", action: nil, keyEquivalent: "")
            ink.submenu = editor.inkMenu()
        }
        return menu
    }

    private static func modifiers(of event: NSEvent) -> EditorShortcuts.Modifiers {
        event.modifierFlags.intersection([.command, .shift, .option, .control])
    }

    // MARK: 한글 조합

    // 조합 중인 글자는 원문에 들어가지만 `textDidChange`가 오지 않는다. 그 글자까지 저장되고
    // 조합 중에 줄이 넘어가도 창 높이가 따라가도록 곧바로 알린다.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if editor?.dismissBlocks() == true { return }
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
        scrollRangeToVisible(self.selectedRange())
        caret?.refresh()
    }

    override func unmarkText() {
        endingComposition { super.unmarkText() }
        editor?.flushPendingChange()
        editor?.compositionDidChange()
        caret?.refresh()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if editor?.dismissBlocks() == true { return }
        let text = (string as? NSAttributedString)?.string ?? (string as? String)
        if let text, editor?.separatesCommittedTrigger(text, replacementRange: replacementRange) == true {
            // 기호를 확정한 뒤 Space를 보낸다. 조합이 없는 입력과 조합 중간 변경에는 적용하지 않는다.
            super.insertText(String(text.dropLast()), replacementRange: replacementRange)
            editor?.compositionDidChange()
            if text.hasSuffix("-") { editor?.splitUndoRecord() }
            super.insertText(String(text.suffix(1)), replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
        editor?.compositionDidChange()
        scrollRangeToVisible(selectedRange())
    }

    // MARK: 마우스

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var topWindowNumber: (NSPoint) -> Int = { NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: 0) }

    private func isTopWindow(for event: NSEvent) -> Bool {
        guard let window else { return false }
        return topWindowNumber(window.convertPoint(toScreen: event.locationInWindow)) == window.windowNumber
    }

    override func mouseEntered(with event: NSEvent) {
        guard isTopWindow(for: event) else { editor?.handleMouseExited(); return }
        super.mouseEntered(with: event)
        updatePointer(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        if editor?.handleMouseDown(at: convert(event.locationInWindow, from: nil)) == true { return }
        selectingWithMouse = true
        window?.invalidateCursorRects(for: self)
        defer { selectingWithMouse = false; window?.invalidateCursorRects(for: self) }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isTopWindow(for: event) else { editor?.handleMouseExited(); return }
        super.mouseMoved(with: event)
        updatePointer(for: event)
    }

    private func updatePointer(for event: NSEvent) {
        guard isHitView(for: event) else {
            editor?.handleMouseExited()
            NSCursor.arrow.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        _ = editor?.handleMouseMoved(at: point)
        editor?.pointer(at: point, selectingText: selectingWithMouse).set()
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
        guard isTopWindow(for: event) else { return }
        guard isHitView(for: event) else {
            NSCursor.arrow.set()
            return
        }
        editor?.pointer(at: convert(event.locationInWindow, from: nil), selectingText: selectingWithMouse).set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        editor?.registerLinkCursorRects()
    }

    override func mouseExited(with event: NSEvent) {
        if isTopWindow(for: event), NSCursor.current == .pointingHand { NSCursor.arrow.set() }
        super.mouseExited(with: event)
        editor?.handleMouseExited()
    }

    private var cursorViewport = NSRect.null

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if cursorViewport != visibleRect {
            cursorViewport = visibleRect
            window?.invalidateCursorRects(for: self)
        }
        guard !trackingAreas.contains(where: { $0.owner === self && $0.userInfo?["editor"] != nil }) else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: ["editor": true]
        ))
        // AppKit은 activeAlways 영역에 cursorUpdate를 전달하지 않는다.
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self
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
        if editor.blockSelection != nil { editor.deleteBlocks(); return }
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
