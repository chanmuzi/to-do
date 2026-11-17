import AppKit

// 되돌리기 기록은 편집기가 직접 든다(`UndoHistory`). 원문 저장소가 바뀔 때마다 그 바꿔 쓰기를 열린 단계에
// 적고, 묶음이 끝나면 닫는다. 바깥이 원문을 바꾸면 적어 둔 위치를 따라 옮긴다(`EditorController+Outside`).
//
// 접힘은 원문에 없는 보기 상태지만 편집을 따라 바뀐다(줄을 옮기면 접힌 줄 번호가 옮겨지고, 토글을 지우면
// 사라진다). 그런 편집을 되돌리면 접힘도 편집 전으로 돌아가야 하므로, 편집이 접힘을 바꿨을 때 그 전 값을
// 같은 단계에 함께 적는다.

extension EditorController {
    /// 사용자의 편집으로 원문이 바뀌었다(`didProcessEditing`). 열린 단계에 적는다.
    func recordForUndo(old: MarkdownDocument, editedRange: NSRange, delta: Int) {
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let edit = UndoEdit(location: editedRange.location, old: old.string(in: oldRange), new: document.string(in: editedRange))
        guard edit.old != edit.new else { return }
        if history.open == nil {
            let selection = selectionBeforeEdit ?? textView.selectedRange()
            history.open = UndoRecord(selectionBefore: selection, selectionAfter: selection)
            history.open?.isTyping = isPlainTyping && edit.old.isEmpty && !edit.new.contains("\n")
            scheduleUndoRecordClose()
        } else {
            history.open?.isTyping = false
        }
        if textView.hasMarkedText() { openRecordIsComposition = true }
        history.open?.edits.append(edit)
    }

    /// 열린 단계를 닫는다. 조합 중이면 조합이 끝난 뒤에 닫는다(조합 하나가 한 단계다).
    func closeUndoRecord() {
        defer { pruneDateEffects() }
        selectionBeforeEdit = nil
        guard let record = history.open, !textView.hasMarkedText() else { return }
        if openRecordIsComposition, record.edits.count > 1 { squashOpenRecord() }
        openRecordIsComposition = false
        history.close(selectionAfter: textView.selectedRange(), coalescesTyping: editorUndoManager.groupsByEvent)
    }

    /// 단계를 여기서 끊는다. 한 번의 입력이 두 단계가 되어야 할 때 쓴다(그 자리에서 바뀐 서식을 되돌리면
    /// 친 기호가 글자로 남는다).
    func splitUndoRecord() {
        closeUndoRecord()
    }

    /// 조합하며 쌓인 편집들을 하나로 줄인다(조합 전의 원문과 지금 원문의 차이).
    private func squashOpenRecord() {
        guard let record = history.open else { return }
        var before = document.text as NSString
        for edit in record.edits.reversed() {
            let range = NSRange(location: edit.location, length: edit.newLength)
            guard NSMaxRange(range) <= before.length else { return }
            before = before.replacingCharacters(in: range, with: edit.old) as NSString
        }
        guard let diff = OutsideEdit(from: before as String, to: document.text) else {
            history.open?.edits = []
            return
        }
        let edit = UndoEdit(location: diff.range.location, old: before.substring(with: diff.range), new: diff.replacement)
        history.open?.edits = [edit]
        history.open?.isTyping = edit.old.isEmpty && !edit.new.contains("\n")
    }

    /// 묶음을 직접 열지 않은 편집은 런 루프 한 차례가 한 단계다.
    private func scheduleUndoRecordClose() {
        guard editorUndoManager.groupingLevel == 0, editorUndoManager.groupsByEvent, !isUndoCloseScheduled else { return }
        isUndoCloseScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isUndoCloseScheduled = false
            guard self.editorUndoManager.groupingLevel == 0 else { return }
            if self.textView.hasMarkedText() {
                // 조합이 끝난 차례에 닫는다.
                self.closesUndoRecordAfterComposition = true
            } else {
                self.closeUndoRecord()
            }
        }
    }

    /// 조합이 끝났을 때. 닫기를 미뤄 둔 단계가 있으면 닫는다.
    func closeUndoRecordAfterCompositionIfNeeded() {
        guard closesUndoRecordAfterComposition, !textView.hasMarkedText() else { return }
        closesUndoRecordAfterComposition = false
        if editorUndoManager.groupingLevel == 0 { closeUndoRecord() }
    }

    /// 되돌리기(또는 다시 하기) 한 단계.
    func replayUndo(redo: Bool) {
        guard let storage = textView.textStorage, textView.isEditable, !isReplayingUndo else { return }
        if textView.hasMarkedText() { textView.unmarkText() }
        closeUndoRecord()
        guard var record = redo ? history.redoStack.last : history.undoStack.last else { return }
        // 적어 둔 글이 그 자리에 그대로 있을 때만 쓴다. 어긋난 단계를 쓰면 엉뚱한 글을 지우거나 엉뚱한 자리에
        // 글을 넣는다. 있어서는 안 되는 일이므로 알리고(디버그 빌드는 멈춘다), 원문은 건드리지 않고 기록을 버린다.
        guard UndoHistory.matches(record, in: document.text, redo: redo) else {
            history = UndoHistory()
            onReplayMismatch("되돌리기 기록이 원문과 어긋났다(\(redo ? "다시 하기" : "되돌리기")). 기록을 버린다")
            return
        }
        if let token = record.dateEffect, let effect = dateEffects[token] {
            do { if redo { try effect.redo() } else { try effect.undo() } }
            catch { onDateError(error); onRejectedEdit(); return }
        }
        if redo { history.redoStack.removeLast() } else { history.undoStack.removeLast() }
        if linkSession != nil { cancelLinkEditing() }
        typingMarks = nil
        pendingPair = nil
        pendingAbsorb = nil
        absorbRun = nil
        codeTag = nil
        swallowsCodeTriggerKey = false
        undoWillReplay()
        for edit in redo ? record.edits : record.edits.reversed() {
            let range = NSRange(location: edit.location, length: redo ? edit.oldLength : edit.newLength)
            let text = redo ? edit.new : edit.old
            guard textView.shouldChangeText(in: range, replacementString: text) else { continue }
            storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: baseAttributes))
        }
        if redo {
            if let target = record.foldsAfter {
                record.foldsBefore = foldsBeforeUndo ?? folded
                pendingFoldRestore = target
            }
            history.pushUndo(record)
        } else {
            if let target = record.foldsBefore {
                record.foldsAfter = foldsBeforeUndo ?? folded
                pendingFoldRestore = target
            }
            history.redoStack.append(record)
        }
        let target = clamped(redo ? record.selectionAfter : record.selectionBefore)
        setSelection(CaretSnapping.snap(old: target, new: target, in: document, folded: folded, textChanged: true))
        textView.didChangeText()
        selectionVersion = documentVersion
        undoDidReplay()
        dismissedDate = (text, selectedRange)
        updateDateSuggestion()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 방금 끝난 편집을 되돌렸을 때 접힘이 저절로 편집 전으로 돌아가지 않으면, 그 전 값을 같은 단계에 적는다.
    ///
    /// 글자를 치는 것처럼 줄 번호만 따라 옮기면 되는 편집은 적지 않는다(되돌리는 편집이 같은 식으로 옮겨 놓는다).
    /// 토글이 사라졌거나, 줄을 옮겼거나, 접힌 덩어리를 통째로 고친 편집은 적는다.
    func recordFoldChangeForUndo() {
        let edits = editsSinceFlush
        let explicit = editSetFoldsExplicitly
        editsSinceFlush = []
        editSetFoldsExplicitly = false
        guard let before = foldsBeforeEdit else { return }
        foldsBeforeEdit = nil
        guard !before.isEmpty || !folded.isEmpty, !isReplayingUndo, history.open != nil else { return }
        if !explicit, edits.count == 1, let edit = edits.first {
            let oldRange = NSRange(location: edit.range.location, length: edit.range.length - edit.delta)
            let redone = FoldState.remapped(before, old: edit.old, new: document, editedRange: edit.range, delta: edit.delta)
            let undone = FoldState.remapped(folded, old: document, new: edit.old, editedRange: oldRange, delta: -edit.delta)
            if redone == folded, undone == before { return }
        }
        // 한 단계에 여럿이 있으면 가장 먼저 적힌 것이 남는다.
        if history.open?.foldsBefore == nil { history.open?.foldsBefore = before }
    }

    private func undoWillReplay() {
        isReplayingUndo = true
        foldsBeforeUndo = folded
        pendingFoldRestore = nil
    }

    private func undoDidReplay() {
        isReplayingUndo = false
        foldsBeforeUndo = nil
        foldsBeforeEdit = nil
        if let target = pendingFoldRestore {
            pendingFoldRestore = nil
            applyFolds(target)
            // 되살린 접힘 안에 선택이 걸려 있으면 접힌 덩어리 밖으로 옮긴다.
            let selection = clamped(textView.selectedRange())
            let snapped = CaretSnapping.snap(old: selection, new: selection, in: document, folded: folded)
            if snapped != selection { setSelection(snapped) }
        }
        notifyFoldChangeIfNeeded()
    }
}
