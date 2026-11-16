import AppKit

// 바깥(이 편집기가 아닌 쪽: 빠른 캡처 등)이 원문을 바꿨을 때, 통째로 갈아 넣지 않고 달라진 부분만 넣는다.
// 통째로 넣으면 되돌리기 기록이 비워지고 조합이 끊기며, 커서가 바깥이 쓴 글 한가운데에 놓일 수 있다.

extension EditorController {
    /// 바깥이 원문 끝에 글을 덧붙였다. `applyOutsideChange`의 한 경우다.
    func appendFromOutside(_ suffix: String) {
        let appended = LineEndings.normalized(suffix)
        guard !appended.isEmpty else { return }
        applyOutsideChange(to: text + appended)
    }

    /// 바깥이 원문을 `newText`로 바꿨다. 규칙은 `MarkdownEditor.applyOutsideChange(to:)`의 주석에 있다.
    func applyOutsideChange(to newText: String) {
        let target = LineEndings.normalized(newText)
        guard target != text else { return }
        // 화면의 원문과 견준다. 미뤄 둔 변경이 있었다면 새 글에 이미 들어 있으므로 갈아 치운다.
        deferredOutsideEdit = nil
        guard let edit = OutsideEdit(from: document.text, to: target) else { return }
        guard textView.hasMarkedText() else {
            perform(edit)
            return
        }
        // 조합 중: 입력기를 거치지 않고 원문 저장소가 바뀌면 텍스트 뷰가 조합을 끝내 버린다. 조합이 끝날
        // 때까지 미룬다. 바뀔 부분이 조합 중인 글자에 겹치면 지킬 수 없으므로 조합을 끝내고 넣는다.
        let marked = textView.markedRange()
        let overlaps = NSIntersectionRange(edit.range, marked).length > 0
            || (edit.range.location > marked.location && edit.range.location < NSMaxRange(marked))
        if overlaps {
            textView.unmarkText()
            if let edit = OutsideEdit(from: document.text, to: target) { perform(edit) }
        } else {
            deferredOutsideEdit = edit
        }
    }

    /// 조합이 끝났으면 미뤄 둔 변경을 넣는다. 조합이 바뀌거나 끝날 때마다 불린다(`flushPendingChange`).
    func applyDeferredOutsideEditIfPossible() {
        guard let edit = deferredOutsideEdit, !textView.hasMarkedText(), !isSettingText, !isApplyingOutsideChange else { return }
        deferredOutsideEdit = nil
        guard NSMaxRange(edit.range) <= document.length else { return }
        perform(edit)
    }

    private func perform(_ edit: OutsideEdit) {
        guard let storage = textView.textStorage else { return }
        let oldLength = document.length
        let selection = clamped(textView.selectedRange())
        let wasPending = hasPendingChange
        let caretWasAtEnd = selection.length == 0 && selection.location == oldLength
        let touchesEnd = NSMaxRange(edit.range) == oldLength
        let replacement = NSAttributedString(string: edit.replacement, attributes: baseAttributes)

        // 되돌리기에 적지 않는다(⌘Z는 바깥이 쓴 글을 지우지도 되살리지도 않는다). 사용자의 기록이 가리키는
        // 위치는 이 변경만큼 따라 옮기고, 이 변경이 사용자가 고친 자리에 겹쳐 옮길 수 없는 단계는 버린다.
        if edit.range.location == 0, edit.range.length == oldLength, oldLength > 0 {
            // 앞뒤로 같은 부분이 하나도 없는 다른 글이다. 지킬 위치가 없다.
            history = UndoHistory()
        } else {
            history.shift(outside: edit.range, delta: edit.delta)
        }
        isApplyingOutsideChange = true
        storage.replaceCharacters(in: edit.range, with: replacement)
        hasPendingChange = wasPending
        selectionVersion = documentVersion

        // 커서와 선택: 바뀐 부분 밖이면 제자리, 안이었으면 바뀐 부분 뒤.
        // 문서 끝의 커서는, 바깥의 글이 커서가 있는 줄에 이어 붙었으면(줄바꿈으로 시작하지 않는다) 그 글 뒤로
        // 보낸다. 제자리에 두면 사용자가 이어 치는 글이 바깥이 쓴 줄의 머리에 끼어든다. 바깥의 글이
        // 줄바꿈으로 시작하면 커서의 줄은 그대로이므로 제자리에 둔다.
        // 앞서 붙은 줄 뒤에서 "이어 치는 글은 새 줄에서"로 기다리던 커서는 새 빈 마지막 줄에 있는 셈이다.
        // 이어서 붙는 글이 줄바꿈으로 시작해도 그 뒤로 따라간다.
        let waitsOnNewLine = caretWasAtEnd && pendingLineBreak.map { $0.location == oldLength } == true
        let sticks = caretWasAtEnd && touchesEnd && (!edit.replacement.hasPrefix("\n") || waitsOnNewLine)
        let start = edit.moved(selection.location, sticksToEnd: sticks)
        let end = selection.length == 0 ? start : max(start, edit.moved(NSMaxRange(selection), sticksToEnd: false))
        setSelection(NSRange(location: start, length: end - start))
        isApplyingOutsideChange = false

        // 바깥이 붙인 글이 줄바꿈으로 끝나지 않으면 커서는 그 줄 끝에 있다. 이어 치는 글은 새 줄에서 시작하게 한다.
        if sticks, start == document.length, start > selection.location, !document.text.hasSuffix("\n") {
            pendingLineBreak = (start, documentVersion)
        } else {
            pendingLineBreak = nil
        }
        refreshStyling()
        reportContentHeight()
        layoutCopyButton()
    }

    /// 그 자리에 정해 둔 줄바꿈이 살아 있으면 거두고 `true`를 돌려준다.
    func takePendingLineBreak(at location: Int) -> Bool {
        guard let pending = pendingLineBreak else { return false }
        pendingLineBreak = nil
        return pending.location == location && pending.version == documentVersion
    }

    /// 조합을 시작하기 전에 정해 둔 줄바꿈을 넣는다(조합 중에는 원문을 따로 고칠 수 없다).
    func insertPendingLineBreakIfNeeded() {
        let caret = textView.selectedRange()
        guard caret.length == 0, takePendingLineBreak(at: caret.location) else { return }
        apply(.insert("\n", replacing: caret))
    }
}
