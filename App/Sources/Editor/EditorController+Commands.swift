import AppKit

extension EditorController {
    /// 편집 동작 하나를 실행한다. 한글 조합 중에는 하지 않는다.
    func run(_ action: EditorAction) {
        guard !textView.hasMarkedText() else { return }
        let selection = clamped(textView.selectedRange())
        switch action {
        case .indent: apply(EditorCommands.indent(document, selection: selection, folded: folded))
        case .outdent: apply(EditorCommands.outdent(document, selection: selection, folded: folded))
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
    /// 접혀서 감춘 줄에 닿는 편집은 `includesHiddenLines`가 없으면 막힌다(`shouldChangeTextIn`).
    func apply(_ edit: TextEdit?) {
        guard let edit, let storage = textView.textStorage, textView.isEditable else { return }
        let wasApplying = isApplyingEdit
        let allowedHidden = allowsHiddenEdit
        isApplyingEdit = true
        allowsHiddenEdit = edit.includesHiddenLines
        defer {
            isApplyingEdit = wasApplying
            allowsHiddenEdit = allowedHidden
        }
        let foldsBefore = folded
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: baseAttributes))
        // 줄을 옮기는 편집은 접힌 줄 번호를 스스로 정하고, 줄 머리만 바꾸는 편집은 줄 번호가 그대로다.
        if let foldedAfter = edit.foldedAfter ?? (edit.preservesLines ? foldsBefore : nil) {
            folded = FoldState.sanitized(foldedAfter, in: document)
            editSetFoldsExplicitly = true
        }
        if edit.includesHiddenLines { editSetFoldsExplicitly = true }
        textView.setSelectedRange(clamped(edit.selection))
        textView.didChangeText()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 감춘 곳으로 옮기지 않고 선택을 그대로 넣는다.
    func setSelection(_ range: NSRange) {
        let wasApplying = isApplyingEdit
        isApplyingEdit = true
        textView.setSelectedRange(clamped(range))
        isApplyingEdit = wasApplying
    }

    /// 선택의 끝이 접힌 줄 안에 들어가 있으면(되돌리기 등) 그 토글을 편다.
    func unfoldAroundSelection() {
        let selection = clamped(textView.selectedRange())
        let lines = Set([selection.location, NSMaxRange(selection)].map(document.lineIndex(at:)))
        let roots = folded.filter { root in
            lines.contains { root < $0 && document.lines[root].subtreeEnd > $0 }
        }
        guard !roots.isEmpty else { return }
        setFolded(folded.subtracting(roots), notify: true)
    }

    /// 원문이 바뀐 것을 바깥에 알린다. 글자 입력은 `textDidChange`에서, 조합 중인 글자는
    /// `setMarkedText` 바로 뒤에 부르고, 그 밖의 경로는 다음 메인 큐 차례에 부른다.
    func flushPendingChange() {
        guard hasPendingChange, !isSettingText else { return }
        hasPendingChange = false
        refreshStyling()
        recordFoldChangeForUndo()
        notifyFoldChangeIfNeeded()
        onTextChange?(document.text)
        reportContentHeight()
        layoutCopyButton()
    }

    /// 원문이 바뀌었다고 적어 두고, 아무도 알리지 않으면 다음 메인 큐 차례에 알리게 한다.
    func markTextChanged() {
        hasPendingChange = true
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFlushScheduled = false
            // 조합 중이 아닌 편집은 `textDidChange`가 곧 온다. 편집 도중에는 끼어들지 않는다.
            guard !self.isApplyingEdit, !self.isReplayingUndo else { return }
            self.flushPendingChange()
        }
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
            apply(EditorCommands.indent(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            apply(EditorCommands.outdent(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertParagraphSeparator(_:)):
            // ⌃Return(U+2028), 문단 구분(U+2029)도 원문에는 `\n` 하나로 넣는다.
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
            if let edit = EditorCommands.deleteForward(document, selection: selection) {
                apply(edit)
                return true
            }
            return false
        default:
            return false
        }
    }

    /// 지우려는 줄바꿈 너머가 접힌 줄이면 먼저 편다. 보이지 않는 줄과 합쳐지지 않게 한다.
    /// 편 뒤에는 보이는 줄끼리 합쳐지므로 그대로 지운다. 그 밖의 지우기(낱말, 줄 끝까지 등)는
    /// `shouldChangeTextIn`이 막는다.
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
        // 속성만 바뀌는 경우.
        guard let replacementString else { return true }
        // 원문이 바뀌는 모든 길목이다. 접혀서 보이지 않는 줄에 닿는 편집은 넣지 않고 그 토글을 편다.
        // 무엇이 바뀌는지 본 뒤에 다시 하게 한다. 되돌리기는 막지 않는다(접힘이 함께 돌아온다).
        if !allowsHiddenEdit, !isReplayingUndo {
            let broken = FoldState.brokenRoots(by: clamped(range), in: document, folded: folded)
            if !broken.isEmpty {
                setFolded(folded.subtracting(broken), notify: true)
                return false
            }
        }
        guard !isApplyingEdit, !isReplayingUndo, !textView.hasMarkedText() else { return true }
        // 붙여넣기, 끌어다 놓기로 들어오는 다른 줄바꿈 글자는 `\n`으로 바꿔 넣는다.
        if LineEndings.needsNormalizing(replacementString) {
            apply(.insert(LineEndings.normalized(replacementString), replacing: clamped(range)))
            return false
        }
        guard replacementString == " ", let edit = EditorCommands.spaceTrigger(document, selection: range) else { return true }
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
        flushPendingChange()
    }
}
