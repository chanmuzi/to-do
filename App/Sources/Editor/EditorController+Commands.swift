import AppKit

extension EditorController {
    /// 편집 동작 하나를 실행한다. 한글 조합 중에는 하지 않는다.
    func run(_ action: EditorAction) {
        guard !textView.hasMarkedText() else { return }
        let selection = clamped(textView.selectedRange())
        switch action {
        case .indent: apply(EditorCommands.indent(document, selection: selection))
        case .outdent: apply(EditorCommands.outdent(document, selection: selection))
        case .toggleTodo: apply(EditorCommands.toggleTodo(document, selection: selection))
        case .toggleDone: apply(EditorCommands.toggleDone(document, selection: selection))
        case .moveLineUp: apply(EditorCommands.moveLines(document, selection: selection, folded: folded, direction: .up))
        case .moveLineDown: apply(EditorCommands.moveLines(document, selection: selection, folded: folded, direction: .down))
        case .heading(let level):
            guard (1...3).contains(level) else { return }
            apply(EditorCommands.toggleHeading(document, selection: selection, level: level))
        case .bold: apply(EditorCommands.toggleWrap(document, selection: selection, .bold))
        case .strikethrough: apply(EditorCommands.toggleWrap(document, selection: selection, .strike))
        case .inlineCode: apply(EditorCommands.toggleWrap(document, selection: selection, .code))
        case .highlight: apply(EditorCommands.cycleHighlight(document, selection: selection))
        case .codeBlock: apply(EditorCommands.toggleCodeBlock(document, selection: selection))
        case .link: apply(EditorCommands.link(document, selection: selection))
        case .fold:
            guard let result = FoldState.fold(document, selection: selection, folded: folded) else { return }
            setSelection(result.selection)
            setFolded(result.folded, notify: true)
        case .unfold:
            guard let unfolded = FoldState.unfold(document, selection: selection, folded: folded) else { return }
            setFolded(unfolded, notify: true)
        }
    }

    /// 원문을 바꿔 쓴다. 텍스트 뷰의 편집 경로를 거치므로 되돌리기 한 단계로 기록된다.
    func apply(_ edit: TextEdit?) {
        guard let edit, let storage = textView.textStorage, textView.isEditable else { return }
        isApplyingEdit = true
        defer { isApplyingEdit = false }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: baseAttributes))
        if let foldedAfter = edit.foldedAfter {
            let sanitized = FoldState.sanitized(foldedAfter, in: document)
            if sanitized != folded {
                folded = sanitized
                foldChangedByEdit = true
            }
        }
        textView.setSelectedRange(clamped(edit.selection))
        textView.didChangeText()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 감춘 곳으로 옮기지 않고 선택을 그대로 넣는다.
    func setSelection(_ range: NSRange) {
        isApplyingEdit = true
        textView.setSelectedRange(clamped(range))
        isApplyingEdit = false
    }

    /// 커서가 접힌 줄 안에 들어가 있으면(되돌리기 등) 그 토글을 편다.
    func unfoldAroundSelection() {
        let selection = clamped(textView.selectedRange())
        guard selection.length == 0 else { return }
        let line = document.lineIndex(at: selection.location)
        let roots = folded.filter { $0 < line && document.lines[$0].subtreeEnd > line }
        guard !roots.isEmpty else { return }
        setFolded(folded.subtracting(roots), notify: true)
    }
}

extension EditorController: NSTextViewDelegate {
    func undoManager(for view: NSTextView) -> UndoManager? {
        editorUndoManager
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // 조합 중인 글자가 있으면 입력기가 먼저 처리하게 둔다.
        guard !textView.hasMarkedText() else { return false }
        let selection = clamped(textView.selectedRange())
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            apply(EditorCommands.indent(document, selection: selection))
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            apply(EditorCommands.outdent(document, selection: selection))
            return true
        case #selector(NSResponder.insertNewline(_:)):
            apply(EditorCommands.newline(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if let edit = EditorCommands.deleteBackward(document, selection: selection) {
                apply(edit)
                return true
            }
            unfoldBeforeDeleting(selection, backward: true)
            return false
        case #selector(NSResponder.deleteForward(_:)):
            unfoldBeforeDeleting(selection, backward: false)
            return false
        default:
            return false
        }
    }

    /// 지우려는 줄바꿈 너머가 접힌 줄이면 먼저 편다. 보이지 않는 줄과 합쳐지지 않게 한다.
    private func unfoldBeforeDeleting(_ selection: NSRange, backward: Bool) {
        guard selection.length == 0 else { return }
        let index = document.lineIndex(at: selection.location)
        let line = document.lines[index]
        if backward, selection.location == line.start, index > 0,
           let root = FoldState.foldRoot(of: index - 1, in: document, folded: folded) {
            setFolded(folded.subtracting([root]), notify: true)
        } else if !backward, selection.location == line.end, folded.contains(index) {
            setFolded(folded.subtracting([index]), notify: true)
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard !isApplyingEdit, !textView.hasMarkedText(), replacementString == " ",
              let edit = EditorCommands.spaceTrigger(document, selection: range) else { return true }
        // `[]` 뒤의 Space: 넣으려던 공백 대신 투두 기호로 바꿔 쓴다.
        apply(edit)
        return false
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldRange: NSRange,
        toCharacterRange newRange: NSRange
    ) -> NSRange {
        guard !isApplyingEdit, !isSettingText, !textView.hasMarkedText() else { return newRange }
        return CaretSnapping.snap(old: oldRange, new: clamped(newRange), in: document, folded: folded)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSettingText else { return }
        if !isApplyingEdit { unfoldAroundSelection() }
        refreshStyling()
    }

    func textDidChange(_ notification: Notification) {
        guard !isSettingText else { return }
        refreshStyling()
        if foldChangedByEdit {
            foldChangedByEdit = false
            onFoldChange?(folded)
        }
        onTextChange?(document.text)
        reportContentHeight()
        layoutCopyButton()
    }
}
