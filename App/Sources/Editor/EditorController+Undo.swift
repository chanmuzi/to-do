import AppKit

// 접힘은 원문에 없는 보기 상태지만 편집을 따라 바뀐다(줄을 옮기면 접힌 줄 번호가 옮겨지고, 토글을 지우면 사라진다).
// 그런 편집을 되돌리면 접힘도 편집 전으로 돌아가야 하므로, 편집이 접힘을 바꿨을 때 그 전 값을 되돌리기에 함께 적는다.

extension EditorController {
    func observeUndo() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
            observers.append(center.addObserver(forName: name, object: editorUndoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.undoWillReplay() }
            })
        }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            observers.append(center.addObserver(forName: name, object: editorUndoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.undoDidReplay() }
            })
        }
    }

    /// 방금 끝난 편집을 되돌렸을 때 접힘이 저절로 편집 전으로 돌아가지 않으면, 그 전 값을 같은 되돌리기 묶음에 적는다.
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
        guard !before.isEmpty || !folded.isEmpty, !isReplayingUndo, editorUndoManager.isUndoRegistrationEnabled,
              editorUndoManager.groupsByEvent || editorUndoManager.groupingLevel > 0 else { return }
        if !explicit, edits.count == 1, let edit = edits.first {
            let oldRange = NSRange(location: edit.range.location, length: edit.range.length - edit.delta)
            let redone = FoldState.remapped(before, old: edit.old, new: document, editedRange: edit.range, delta: edit.delta)
            let undone = FoldState.remapped(folded, old: document, new: edit.old, editedRange: oldRange, delta: -edit.delta)
            if redone == folded, undone == before { return }
        }
        registerFoldRestore(before)
    }

    private func registerFoldRestore(_ target: Set<Int>) {
        editorUndoManager.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.restoreFolds(target) }
        }
    }

    /// 되돌리기, 다시 하기 도중에 불린다. 원문이 모두 돌아온 뒤(`undoDidReplay`)에 접힘을 넣는다.
    /// 한 묶음에 여럿이 있으면 마지막에 불린 것(가장 먼저 적힌 것)이 남는다.
    private func restoreFolds(_ target: Set<Int>) {
        registerFoldRestore(foldsBeforeUndo ?? folded)
        pendingFoldRestore = target
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
