import AppKit
import DateTime
import Models
import Theme

extension TitleField {
    func updateDateSuggestion() {
        guard let editor = currentEditor() as? NSTextView else { hideDateSuggestion(); return }
        let text = editor.string
        let selection = editor.selectedRange()
        dateSuggestion = nil
        if isEditing, onAcceptDate != nil, !editor.hasMarkedText(), selection.length == 0,
           !(dismissedDate?.text == text && dismissedDate?.selection == selection) {
            let excluded = Self.dateExclusions.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).map(\.range)
            dateSuggestion = InlineDateProposal.find(in: text, caret: selection.location, now: Date(),
                                                     calendar: .current, excluding: excluded)
        }
        let whole = NSRange(location: 0, length: editor.string.utf16.count)
        editor.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
        editor.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
        for range in dateSuggestion?.expression.ranges ?? [] {
            editor.layoutManager?.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                                                         .underlineColor: style.color(.text)], forCharacterRange: range)
        }
        let message = dateSuggestion.map {
            let p = ReminderPresentation(item: $0.item, now: Date(), options: NoteDisplayOptions(), calendar: .current)
            return ($0.item.kind == .event ? "일정 " : "리마인더 ") + (p.text ?? "")
        }
        dateHint.prepare(message)
        layoutDateHint()
        setAccessibilityHelp(message)
    }
    private static let dateExclusions = try! NSRegularExpression(pattern: #"`[^`]*`|\]\([^)]*\)|https?://\S+"#)

    func hideDateSuggestion() {
        dateSuggestion = nil
        dateHint.prepare(nil)
        setDatePreviewHeight(0)
        setAccessibilityHelp(nil)
    }

    func observeDateSelection(_ editor: NSTextView) {
        if let dateObserver { NotificationCenter.default.removeObserver(dateObserver) }
        dateObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
            object: editor, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateDateSuggestion() }
            }
        updateDateSuggestion()
    }

    func acceptDateSuggestion(in editor: NSTextView) -> Bool {
        guard dateSuggestion != nil else { return false }
        updateDateSuggestion()
        guard let proposal = dateSuggestion, !editor.hasMarkedText(), let accept = onAcceptDate,
              let undo = editor.undoManager else { return true }
        let before = editor.string
        let selection = editor.selectedRange()
        let after = proposal.removingFromTitle(before)
        do {
            let effect = try accept(InlineDateAcceptance(item: proposal.item,
                source: InlineScheduleSource(line: nil, text: after), todo: nil, previousText: before, nextText: after))
            editor.breakUndoCoalescing()
            undo.beginUndoGrouping()
            // AppKit의 글자 undo와 별개로 등록하면 두 번 눌러야 한다. 이 변경 전체를 한 동작으로 적는다.
            replaceTitle(after, selection: selectionAfterRemovingDate(before: before, after: after, selection: selection))
            undo.registerUndo(withTarget: self) { [weak undo] target in
                guard let undo else { return }
                target.replayDate(before: before, after: after, selection: selection, effect: effect, redo: false, manager: undo)
            }
            undo.endUndoGrouping()
            titleBeforeEditing = after
            hideDateSuggestion()
        } catch { onDateError(error); NSSound.beep() }
        return true
    }

    private func selectionAfterRemovingDate(before: String, after: String, selection: NSRange) -> NSRange {
        let removed = before.utf16.count - after.utf16.count
        return NSRange(location: min(after.utf16.count, max(0, selection.location - removed)), length: 0)
    }

    func setDatePreviewHeight(_ height: CGFloat) {
        guard datePreviewHeight != height else { return }
        datePreviewHeight = height
        onDatePreviewHeightChange?()
    }

    func layoutDateHint() {
        guard !isLayingOutDateHint else { return }
        isLayingOutDateHint = true
        defer { isLayingOutDateHint = false }
        guard dateSuggestion != nil, let editor = currentEditor() as? NSTextView,
              let host = superview, let window else { dateHint.hide(); setDatePreviewHeight(0); return }
        let range = editor.selectedRange()
        let screen = editor.firstRect(forCharacterRange: range, actualRange: nil)
        let caret = host.convert(window.convertFromScreen(screen), from: nil)
        let field = host.convert(bounds, from: self)
        let pad = style.theme.space(.sp2)
        let size = dateHint.preferredSize
        let fits = range.location == editor.string.utf16.count && caret.maxX + pad + size.width <= field.maxX
            && size.height <= field.height
        setDatePreviewHeight(fits ? 0 : size.height + pad)
        if fits {
            dateHint.place(in: host, area: NSRect(x: caret.maxX + pad, y: field.midY - size.height / 2,
                width: size.width, height: size.height))
        } else {
            // TopRowView는 이 칸 위에 datePreviewHeight만큼 자리를 비운다.
            let y = host.isFlipped ? field.minY - pad - size.height : field.maxY + pad
            dateHint.place(in: host, area: NSRect(x: field.minX, y: y,
                width: max(0, field.width), height: size.height))
        }
    }

    private func replaceTitle(_ text: String, selection: NSRange) {
        if let editor = currentEditor() as? NSTextView, let storage = editor.textStorage {
            // string/stringValue 대입은 필드 편집기의 undo 관리자를 초기화한다.
            // 저장소의 글자만 바꾸고 기존 기록은 그대로 둔다.
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            editor.setSelectedRange(selection)
            editor.didChangeText()
        } else { stringValue = text }
        dismissedDate = (text, selection)
        onChange?(text)
    }

    private func replayDate(before: String, after: String, selection: NSRange,
                            effect: InlineDateEffect, redo: Bool, manager: UndoManager) {
        guard (currentEditor()?.string ?? stringValue) == (redo ? before : after) else { NSSound.beep(); return }
        do {
            if redo { try effect.redo() } else { try effect.undo() }
            let restored = redo ? after : before
            replaceTitle(restored, selection: redo ? selectionAfterRemovingDate(before: before, after: after, selection: selection) : selection)
            titleBeforeEditing = restored
            manager.registerUndo(withTarget: self) { [weak manager] target in
                guard let manager else { return }
                target.replayDate(before: before, after: after, selection: selection, effect: effect, redo: !redo, manager: manager)
            }
            updateDateSuggestion()
        } catch { onDateError(error); NSSound.beep() }
    }
}
