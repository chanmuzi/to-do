import AppKit

// 조합(한글 입력)이 시작되면 원문을 따로 고칠 수 없다(조합이 끊긴다). 그래서 조합을 시작하기 직전에만
// 자리를 만들고, 조합이 글자 없이 끝나면 만들어 둔 것을 치운다.

extension EditorController {
    /// 입력기가 기호와 마지막 Space를 한 번에 확정하면 delegate가 아직 marked text를 보고
    /// 변환을 건너뛴다. 변환 가능한 줄 머리에 한해 확정과 Space를 나눠 기존 입력 경로로 보낸다.
    func separatesCommittedTrigger(_ text: String, replacementRange: NSRange) -> Bool {
        guard textView.hasMarkedText(), text.hasSuffix(" "), !isApplyingEdit, !isReplayingUndo else { return false }
        let range = replacementRange.location == NSNotFound ? textView.markedRange() : replacementRange
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= document.length else { return false }
        let prefix = String(text.dropLast())
        let committed = (document.text as NSString).replacingCharacters(in: range, with: prefix)
        let candidate = MarkdownDocument(committed)
        return EditorCommands.spaceTrigger(candidate, selection: NSRange(location: range.location + prefix.utf16.count, length: 0)) != nil
    }

    /// 조합이 시작되기 직전. 조합 중에는 원문을 고쳐 쓸 수 없으므로(조합이 끊긴다) 그 전에 자리를 만든다:
    /// 선택을 덮어쓰는 조합이면 선택을 먼저 기호와 함께 지우고, 정해 둔 서식이 있으면 빈 기호 쌍을 넣는다.
    func prepareForComposition() {
        guard !isApplyingEdit, !isReplayingUndo, !isEndingComposition, textView.isEditable else { return }
        swallowsCodeTriggerKey = false
        codeTag = nil
        let absorb = absorbRun
        absorbRun = nil
        let original = clamped(textView.selectedRange())
        let selection = EditorCommands.normalized(document, original, replacement: "가")
        if selection != original { setSelection(selection) }
        // 글자로 덮어쓸 때와 같은 규칙이다: 그대로 덮어써도 되는 선택(구간의 글자를 모두 고른 경우 등)은
        // 입력기에 맡기고, 기호가 짝을 잃는 선택만 먼저 지운다.
        if selection.length > 0 {
            if EditorCommands.replacing(document, selection, with: "가") != nil {
                if let edit = EditorCommands.replacing(document, selection, with: "") { apply(edit) }
            } else if replacingMovesOrphans(selection) {
                // 부모 줄을 덮어쓰는 조합: 조합 중에는 하위 줄을 함께 내어 쓸 수 없으므로 선택을 먼저 지운다
                // (지우는 편집이 하위 줄을 내어 쓴다). 영문으로 덮어쓴 것과 같은 글이 남는다(D-043).
                apply(.insert("", replacing: selection))
            } else {
                // 구간의 글자를 모두 고르고 조합한다. 조합이 글자 없이 끝나면 빈 기호 쌍이 남으므로 적어 둔다.
                let line = document.line(at: selection.location)
                var covered = selection
                var before = ""
                var after = ""
                while let span = line.markedSpans.first(where: { $0.contentRange == covered }) {
                    before = document.string(in: span.openMarker) + before
                    after += document.string(in: span.closeMarker)
                    covered = span.range
                }
                if !before.isEmpty || !after.isEmpty { pendingPair = (selection.location, before, after) }
                return
            }
        }
        insertPendingLineBreakIfNeeded()
        let caret = textView.selectedRange()
        guard caret.length == 0 else { return }
        // 줄이 없는 코드 블록의 커서 자리: 조합할 빈 코드 줄을 먼저 만든다.
        if let block = EditorCommands.emptyBlock(document, caretAt: caret.location) {
            apply(EditorCommands.insertingIntoEmptyBlock(document, block, ""))
            return
        }
        // 구간 끝에서 친 공백 뒤: 공백을 구간 안으로 들이고 그 뒤에서 조합한다.
        if let absorb, absorb.location == caret.location, absorb.version == documentVersion,
           let edit = EditorCommands.absorbingIntoRun(document, closeStart: absorb.closeStart, caret: caret.location, text: "") {
            let closes = edit.replacement.utf16.count - (edit.selection.location - edit.range.location)
            let text = edit.replacement as NSString
            apply(edit, isIntermediate: true)
            pendingAbsorb = (absorb.closeStart, text.substring(to: text.length - closes), text.substring(from: text.length - closes))
            return
        }
        guard let marks = currentTypingMarks() else { return }
        typingMarks = nil
        guard let edit = EditorCommands.materialize(document, caret: caret.location, marks: marks) else { return }
        if edit.replacement.isEmpty {
            setSelection(edit.selection)
            return
        }
        apply(edit)
        let before = edit.selection.location - edit.range.location
        let text = edit.replacement as NSString
        pendingPair = (edit.selection.location, text.substring(to: before), text.substring(from: before))
    }

    /// 선택을 글자로 덮어쓰면 부모를 잃는 하위 줄을 함께 내어 써야 하는지.
    private func replacingMovesOrphans(_ selection: NSRange) -> Bool {
        let typed = TextEdit.insert("가", replacing: selection)
        let adopted = EditorCommands.adoptingOrphans(document, typed, folded: folded)
        return adopted.range != typed.range || adopted.replacement != typed.replacement
    }

    /// 조합이 바뀌거나 끝난 뒤. 조합이 글자 없이 끝났으면 넣어 둔 빈 기호 쌍을 지운다(구간의 글자를 모두
    /// 고르고 조합하다 그만둔 경우도 같다. 다른 지우기처럼 빈 구간의 기호를 함께 지운다).
    func compositionDidChange() {
        defer { updateDateSuggestion() }
        // 텍스트 뷰가 조합을 끝내는 중에는 조합 중인 글자가 잠깐 비어 보인다. 끝난 뒤에 다시 불린다.
        guard !isEndingComposition else { return }
        closeUndoRecordAfterCompositionIfNeeded()
        guard !textView.hasMarkedText(), !isApplyingEdit, !isReplayingUndo else { return }
        if let absorb = pendingAbsorb {
            pendingAbsorb = nil
            let moved = absorb.space + absorb.closes
            let range = NSRange(location: absorb.closeStart, length: moved.utf16.count)
            if NSMaxRange(range) <= document.length, document.string(in: range) == moved,
               textView.selectedRange() == NSRange(location: absorb.closeStart + absorb.space.utf16.count, length: 0) {
                apply(TextEdit(range: range, replacement: absorb.closes + absorb.space, selection: NSRange(location: NSMaxRange(range), length: 0)))
            }
        }
        guard let pair = pendingPair else { return }
        pendingPair = nil
        let range = NSRange(
            location: pair.location - pair.before.utf16.count,
            length: pair.before.utf16.count + pair.after.utf16.count
        )
        guard range.location >= 0, NSMaxRange(range) <= document.length,
              document.string(in: range) == pair.before + pair.after else { return }
        apply(TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0)))
    }
}
