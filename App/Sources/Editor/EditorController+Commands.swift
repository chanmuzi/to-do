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
        case .bold: toggle(.bold, selection: selection)
        case .strikethrough: toggle(.strike, selection: selection)
        case .inlineCode: toggle(.code, selection: selection)
        case .highlight:
            if selection.length > 0 {
                apply(EditorCommands.cycleHighlight(document, selection: selection))
            } else {
                perform(EditorCommands.cycleTypingHighlight(document, caret: selection.location, marks: currentTypingMarks() ?? TypingMarks()))
            }
        case .codeBlock: apply(EditorCommands.toggleCodeBlock(document, selection: selection))
        case .link: beginLinkEditing()
        case .fold:
            guard let result = FoldState.fold(document, selection: selection, folded: folded) else { return }
            setSelection(result.selection)
            setFolded(result.folded, notify: true)
        case .unfold:
            guard let unfolded = FoldState.unfold(document, selection: selection, folded: folded) else { return }
            setFolded(unfolded, notify: true)
        }
    }

    /// 굵게, 취소선, 인라인 코드. 선택이 있으면 그 글자에, 없으면 다음에 칠 글자에 건다.
    private func toggle(_ wrap: EditorCommands.Wrap, selection: NSRange) {
        if selection.length > 0 {
            apply(EditorCommands.toggleWrap(document, selection: selection, wrap))
        } else {
            perform(EditorCommands.toggleTyping(document, caret: selection.location, wrap, marks: currentTypingMarks() ?? TypingMarks()))
        }
    }

    private func perform(_ toggle: TypingToggle) {
        switch toggle {
        case .move(let location):
            typingMarks = nil
            setSelection(NSRange(location: location, length: 0))
        case .marks(let marks):
            let location = clamped(textView.selectedRange()).location
            typingMarks = marks.isEmpty ? nil : (location, documentVersion, marks)
        case .unavailable:
            break
        }
    }

    /// 정해 둔 "다음에 칠 글자의 서식". 커서가 그 자리에 그대로 있고 원문이 그대로일 때만 살아 있다.
    func currentTypingMarks() -> TypingMarks? {
        guard let typingMarks else { return nil }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location == typingMarks.location,
              typingMarks.version == documentVersion else {
            self.typingMarks = nil
            return nil
        }
        return typingMarks.marks
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
        selectionVersion = documentVersion
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func apply(_ outcome: KeyOutcome) -> Bool {
        switch outcome {
        case .edit(let edit):
            apply(edit)
            return true
        case .select(let range):
            setSelection(range)
            return true
        case .ignore:
            return true
        case .passThrough:
            return false
        }
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
        applyDeferredOutsideEditIfPossible()
        selectionVersion = documentVersion
        // 바깥의 변경을 넣는 중에는 알리지 않는다. 알리지 않은 사용자의 변경은 다음 차례에 나간다.
        guard hasPendingChange, !isSettingText, !isApplyingOutsideChange else { return }
        hasPendingChange = false
        refreshStyling()
        recordFoldChangeForUndo()
        notifyFoldChangeIfNeeded()
        // 미뤄 둔 덧붙임(글 끝에서 조합 중)이 있으면 그것까지가 원문이다.
        onTextChange?(text)
        reportContentHeight()
        layoutCopyButton()
    }

    /// 바깥이 지금 알려 달라고 했다(창을 닫기 직전 등). 편집이나 되돌리기가 진행 중이면 그것이 끝나며 알린다.
    func flushPendingChangeNow() {
        guard !isApplyingEdit, !isReplayingUndo else { return }
        flushPendingChange()
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

    // MARK: 조합(한글 입력)

    /// 조합이 시작되기 직전. 조합 중에는 원문을 고쳐 쓸 수 없으므로(조합이 끊긴다) 그 전에 자리를 만든다:
    /// 선택을 덮어쓰는 조합이면 선택을 먼저 기호와 함께 지우고, 정해 둔 서식이 있으면 빈 기호 쌍을 넣는다.
    func prepareForComposition() {
        guard !isApplyingEdit, !isReplayingUndo, textView.isEditable else { return }
        swallowsCodeTriggerKey = false
        let selection = clamped(textView.selectedRange())
        // 글자로 덮어쓸 때와 같은 규칙이다: 그대로 덮어써도 되는 선택(구간의 글자를 모두 고른 경우 등)은
        // 입력기에 맡기고, 기호가 짝을 잃는 선택만 먼저 지운다.
        if selection.length > 0, EditorCommands.replacing(document, selection, with: "가") != nil,
           let edit = EditorCommands.replacing(document, selection, with: "") {
            apply(edit)
        }
        insertPendingLineBreakIfNeeded()
        let caret = textView.selectedRange()
        guard caret.length == 0, let marks = currentTypingMarks() else { return }
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

    /// 조합이 바뀌거나 끝난 뒤. 조합이 글자 없이 끝났으면 넣어 둔 빈 기호 쌍을 지운다.
    func compositionDidChange() {
        guard !textView.hasMarkedText(), !isApplyingEdit, !isReplayingUndo, let pair = pendingPair else { return }
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

extension EditorController: NSTextViewDelegate {
    func undoManager(for view: NSTextView) -> UndoManager? {
        editorUndoManager
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // 조합 중인 글자가 있으면 입력기가 먼저 처리하게 둔다.
        guard !textView.hasMarkedText() else { return false }
        let selection = clamped(textView.selectedRange())
        let swallows = swallowsCodeTriggerKey
        swallowsCodeTriggerKey = false
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
            // 세 번째 백틱으로 코드 블록이 이미 만들어졌다. 이어 누른 Return은 넣지 않는다.
            if swallows { return true }
            // ⌃Return(U+2028), 문단 구분(U+2029)도 원문에는 `\n` 하나로 넣는다.
            apply(EditorCommands.newline(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            unfoldBeforeDeleting(selection, backward: true)
            return apply(EditorCommands.deleteBackward(document, selection: selection))
        case #selector(NSResponder.deleteForward(_:)):
            unfoldBeforeDeleting(selection, backward: false)
            return apply(EditorCommands.deleteForward(document, selection: selection))
        case #selector(NSResponder.moveDown(_:)):
            // 문서 끝의 코드 블록에서 아래로 나가면 빈 문단을 만든다.
            guard isOnEdgeVisualLine(selection.location, last: true),
                  let edit = EditorCommands.leaveCodeBlockDownward(document, selection: selection) else { return false }
            apply(edit)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard isOnEdgeVisualLine(selection.location, last: false),
                  let edit = EditorCommands.leaveCodeBlockUpward(document, selection: selection) else { return false }
            apply(edit)
            return true
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
        if backward, line.prefixLength == 0, line.isVisualStart(selection.location), index > 0,
           let root = FoldState.foldRoot(of: index - 1, in: document, folded: folded) {
            setFolded(folded.subtracting([root]), notify: true)
        } else if !backward, !line.kind.isCode, line.isVisualEnd(selection.location), folded.contains(index) {
            setFolded(folded.subtracting([index]), notify: true)
        }
    }

    /// 그 위치가 문단의 마지막(또는 첫) 화면 줄에 있는지. 줄이 넘어간 문단에서 ↑↓가 문단 안을 움직일 때를 가린다.
    private func isOnEdgeVisualLine(_ location: Int, last: Bool) -> Bool {
        let line = document.line(at: location)
        guard let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: line.start),
              let fragment = layoutManager.textLayoutFragment(for: start) else { return true }
        layoutManager.ensureLayout(for: fragment.rangeInElement)
        let lines = fragment.textLineFragments.filter { $0.characterRange.length > 0 }
        guard let edge = last ? lines.last : lines.first else { return true }
        let offset = location - line.start
        return last ? offset >= edge.characterRange.location : offset <= NSMaxRange(edge.characterRange)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        // 속성만 바뀌는 경우.
        guard let replacementString else { return true }
        // 바깥이 바꾼 글은 그대로 받는다(감춘 줄에 닿으면 넣은 뒤에 그 토글을 편다).
        if isApplyingOutsideChange { return true }
        // 원문이 바뀌는 모든 길목이다. 접혀서 보이지 않는 줄에 닿는 편집은 넣지 않고 그 토글을 편다.
        // 무엇이 바뀌는지 본 뒤에 다시 하게 한다. 되돌리기는 막지 않는다(접힘이 함께 돌아온다).
        if !allowsHiddenEdit, !isReplayingUndo {
            let broken = FoldState.brokenRoots(by: clamped(range), in: document, folded: folded)
            if !broken.isEmpty {
                setFolded(folded.subtracting(broken), notify: true)
                return false
            }
        }
        // 보이지 않는 ``` 줄의 한쪽만 지워지는 편집은 넣지 않는다(편집 명령은 스스로 맞춰 쓴다).
        if !isApplyingEdit, !isReplayingUndo, EditorCommands.breaksCodeFence(document, clamped(range)) {
            return false
        }
        guard !isApplyingEdit, !isReplayingUndo, !textView.hasMarkedText() else { return true }
        let range = clamped(range)
        let text = LineEndings.normalized(replacementString)
        let swallows = swallowsCodeTriggerKey
        swallowsCodeTriggerKey = false

        if range.length == 0 {
            // 바깥이 줄바꿈 없이 붙인 줄의 끝에 커서가 있다. 이어 치는 글은 새 줄에서 시작한다.
            if !text.isEmpty, !text.hasPrefix("\n"), takePendingLineBreak(at: range.location) {
                apply(.insert("\n" + text, replacing: range))
                return false
            }
            // 세 번째 백틱으로 코드 블록이 이미 만들어졌다. 이어 누른 Space는 넣지 않는다.
            if swallows, text == " " { return false }
            // 정해 둔 서식이 있으면 기호 쌍과 함께 넣는다(한 번의 편집).
            if !text.isEmpty, let marks = currentTypingMarks() {
                typingMarks = nil
                if let place = EditorCommands.materialize(document, caret: range.location, marks: marks) {
                    let before = place.selection.location - place.range.location
                    let pair = place.replacement as NSString
                    let inserted = pair.substring(to: before) + text
                    apply(TextEdit(
                        range: place.range,
                        replacement: inserted + pair.substring(from: before),
                        selection: NSRange(location: place.range.location + inserted.utf16.count, length: 0)
                    ))
                    return false
                }
            }
            // 줄 맨 앞의 기호 뒤 Space, 세 번째 백틱: 줄의 종류를 바꾼다.
            if text == " ", let edit = EditorCommands.spaceTrigger(document, selection: range) {
                apply(edit)
                return false
            }
            if text == "`", let edit = EditorCommands.codeBlockTrigger(document, selection: range) {
                apply(edit)
                swallowsCodeTriggerKey = true
                return false
            }
        }
        // 감춘 기호가 짝을 잃지 않게 고쳐 쓴다(선택을 지우거나 덮어쓸 때, 구간 안에 여러 줄을 넣을 때).
        if let edit = EditorCommands.replacing(document, range, with: text) {
            apply(edit)
            return false
        }
        // 붙여넣기, 끌어다 놓기로 들어오는 다른 줄바꿈 글자는 `\\n`으로 바꿔 넣는다.
        if text != replacementString {
            apply(.insert(text, replacing: range))
            return false
        }
        return true
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldRange: NSRange,
        toCharacterRange newRange: NSRange
    ) -> NSRange {
        guard !isApplyingEdit, !isSettingText, !textView.hasMarkedText() else { return newRange }
        return CaretSnapping.snap(
            old: clamped(oldRange),
            new: clamped(newRange),
            in: document,
            folded: folded,
            textChanged: selectionVersion != documentVersion || isReplayingUndo
        )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSettingText else { return }
        if !isApplyingEdit {
            unfoldAroundSelection()
            swallowsCodeTriggerKey = false
            // 커서를 옮기면 정해 둔 "다음에 칠 글자의 서식"은 사라진다(제자리로 돌아와도).
            typingMarks = nil
            if !isApplyingOutsideChange { pendingLineBreak = nil }
        }
        selectionVersion = documentVersion
        refreshStyling()
    }

    func textDidChange(_ notification: Notification) {
        flushPendingChange()
    }
}
