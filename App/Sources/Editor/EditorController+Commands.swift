import AppKit

extension EditorController {
    /// 굵게는 조합한 글자를 먼저 확정하고 그 뒤의 입력 상태를 바꾼다.
    func run(_ action: EditorAction) {
        defer { onFormattingChange?() }
        if textView.hasMarkedText() {
            guard action == .bold else { return }
            textView.unmarkText()
            textView.inputContext?.discardMarkedText()
        }
        let selection = clamped(textView.selectedRange())
        switch action {
        case .indent: apply(EditorCommands.indent(document, selection: selection, folded: folded))
        case .outdent: apply(EditorCommands.outdent(document, selection: selection, folded: folded))
        case .toggleBullet: apply(EditorCommands.toggleBullet(document, selection: selection))
        case .toggleTodo: apply(EditorCommands.toggleTodo(document, selection: selection))
        case .toggleDone:
            let lines = document.lineRange(for: selection)
            let first = lines.lowerBound
            if lines.count == 1, document.lines[first].kind.isToggle {
                if document.lines[first].subtreeEnd > first + 1 { toggleFold(line: first) }
            } else {
                apply(EditorCommands.toggleDone(document, selection: selection))
            }
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
                perform(EditorCommands.cycleTypingHighlight(document, caret: selection.location, marks: marksForShortcut()))
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
            let toggle = EditorCommands.toggleTyping(document, caret: selection.location, wrap, marks: marksForShortcut())
            perform(toggle)
        }
    }

    /// 구간 끝의 공백 뒤에서는 다음 글자가 앞 구간의 서식을 이어받는다.
    var continuingRunEnd: Int? {
        guard let run = absorbRun, run.version == documentVersion,
              selectedRange == NSRange(location: run.location, length: 0) else { return nil }
        return run.closeStart
    }

    private func marksForShortcut() -> TypingMarks {
        guard continuingRunEnd != nil else { return currentTypingMarks() ?? TypingMarks() }
        let state = formattingState
        absorbRun = nil
        return TypingMarks(bold: state.bold ? true : nil, strike: state.strikethrough ? true : nil,
                           code: state.inlineCode ? true : nil, highlight: state.highlight == 0 ? nil : state.highlight)
    }

    var formattingState: EditorFormattingState {
        let selection = clamped(selectedRange)
        let line = document.line(at: selection.location)
        var range = selection
        if let end = continuingRunEnd {
            range = NSRange(location: end, length: 0)
        } else if selection.length > 0, let inline = EditorCommands.inlineLine(document, selection) {
            range = EditorCommands.visibleSelection(selection, in: inline) ?? selection
        }
        let spans = line.spansContaining(range.location).filter { NSMaxRange($0.contentRange) >= NSMaxRange(range) }
        let marks = currentTypingMarks()
        let highlight = spans.compactMap { span -> Int? in
            if case .highlight(let color) = span.kind { return color }
            return nil
        }.first
        return EditorFormattingState(
            bold: marks?.bold ?? spans.contains { $0.kind == .bold },
            strikethrough: marks?.strike ?? spans.contains { $0.kind == .strike },
            inlineCode: marks?.code ?? spans.contains { $0.kind == .code },
            highlight: marks?.highlight ?? highlight ?? 0,
            link: spans.contains { if case .link = $0.kind { true } else { false } },
            checklist: document.lineRange(for: selection).allSatisfy { if case .todo = document.lines[$0].kind { true } else { false } },
            bullet: document.lineRange(for: selection).allSatisfy { document.lines[$0].kind == .bullet }
        )
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
    /// - Parameter isIntermediate: 곧 이어지는 편집이나 조합이 마무리하는 중간 편집(두 단계로 넣는 서식의 둘째
    ///   단계, 조합할 자리를 만드는 편집). 그 사이에 잠깐 드러나는 기호는 가리지 않는다.
    func apply(_ edit: TextEdit?, isIntermediate: Bool = false) {
        guard var edit, let storage = textView.textStorage, textView.isEditable else { return }
        // 부모 항목을 없앤 편집은 부모를 잃는 하위 줄을 함께 내어 쓴다(D-043. `finalized`에서 이미 따진 편집은 다시 따지지 않는다).
        if !isIntermediate { edit = EditorCommands.adoptingOrphans(document, edit, folded: folded) }
        // ``` 줄이 짝을 잃는 편집은 그대로 넣지 않는다(어느 길로 들어온 편집이든). 새로 생기는 ``` 를 글자로
        // 막아 넣을 수 있으면 그렇게 하고, 아니면 넣지 않고 알린다.
        if !EditorCommands.keepsFencesBalanced(document, edit) {
            guard let repaired = EditorCommands.escapingNewFences(document, edit) else {
                onRejectedEdit()
                return
            }
            edit = repaired
        }
        // 감춰 둔 기호가 글자로 드러나는 편집도 넣지 않는다(있던 서식을 원문에 적을 수 없게 된다).
        guard isIntermediate || !EditorCommands.exposesHiddenMarkers(document, edit) else {
            onRejectedEdit()
            return
        }
        let wasApplying = isApplyingEdit
        let allowedHidden = allowsHiddenEdit
        isPlainTyping = false
        if history.open == nil { selectionBeforeEdit = textView.selectedRange() }
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
        // 명령이 정한 커서가 감춘 곳(줄 머리, 기호 한가운데, ``` 줄)에 걸리면 보이는 자리로 옮긴다.
        let target = clamped(edit.selection)
        textView.setSelectedRange(CaretSnapping.snap(old: target, new: target, in: document, folded: folded, textChanged: true))
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
        // 쌓아 두는 중이거나 텍스트 뷰가 조합을 끝내는 중이면 끝난 뒤에 한 번만 알린다.
        guard !holdsChangeNotification, !isEndingComposition else { return }
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
        onFormattingChange?()
        reportContentHeight()
        layoutCopyButton()
        updateDateSuggestion()
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
}

extension EditorController: NSTextViewDelegate {
    func undoManager(for view: NSTextView) -> UndoManager? {
        editorUndoManager
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // 조합 중인 글자가 있으면 입력기가 먼저 처리하게 둔다.
        if textView.hasMarkedText() {
            // 입력기가 처리한 뒤에도 조합이 남아 있으면 Tab이 조합 글자를 덮어쓰지 않게 한다.
            return onAcceptDate != nil && (selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)))
        }
        let selection = clamped(textView.selectedRange())
        let swallows = swallowsCodeTriggerKey
        swallowsCodeTriggerKey = false
        let tag = codeTag
        codeTag = nil
        absorbRun = nil
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)) where dateSuggestion != nil:
            return dismissDateSuggestion()
        case #selector(NSResponder.insertTab(_:)):
            if selection.length == 0, acceptDateSuggestion() { return true }
            apply(EditorCommands.indent(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            if let edit = EditorCommands.outdent(document, selection: selection, folded: folded) {
                apply(edit)
            } else if selection == NSRange(location: 0, length: 0), !document.lines[0].kind.isListItem {
                onFocusTitle?()
            }
            return true
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertParagraphSeparator(_:)):
            // 세 번째 백틱으로 코드 블록이 이미 만들어졌다. 이어 누른 Return은 넣지 않는다.
            if swallows { return true }
            // 블록을 만든 바로 뒤에 친 낱말 하나는 언어 이름이다(` ```swift ` + Return).
            if let tag, let edit = EditorCommands.languageTag(document, selection: selection, openLine: tag.openLine, typed: tag.typed) {
                apply(edit)
                return true
            }
            // ⌃Return(U+2028), 문단 구분(U+2029)도 원문에는 `\n` 하나로 넣는다.
            apply(EditorCommands.newline(document, selection: selection, folded: folded))
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            unfoldBeforeDeleting(selection, backward: true)
            return apply(finalized(EditorCommands.deleteBackward(document, selection: selection)))
        case #selector(NSResponder.deleteForward(_:)):
            unfoldBeforeDeleting(selection, backward: false)
            return apply(finalized(EditorCommands.deleteForward(document, selection: selection)))
        case #selector(NSResponder.transpose(_:)):
            return apply(finalized(EditorCommands.transpose(document, selection: selection)))
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

    private func finalized(_ outcome: KeyOutcome) -> KeyOutcome {
        guard case .edit(let edit) = outcome else { return outcome }
        guard let finalized = finalized(edit) else { return .ignore }
        return .edit(finalized)
    }

    /// 사용자의 편집을 다듬는다(`EditorCommands.finalized`). 있던 서식 구간을 읽히지 않게 만드는 편집
    /// (구간 바로 앞에 영문자나 숫자가 붙는다)은 넣지 않고 알린 뒤 `nil`을 돌려준다. 서식을 말없이 풀지 않는다.
    private func finalized(_ edit: TextEdit) -> TextEdit? {
        guard !EditorCommands.breaksExistingRun(document, edit) else {
            onRejectedEdit()
            return nil
        }
        // 지우거나 덮어써 부모 항목이 없어지면 하위 줄을 함께 내어 쓴다(그대로 넣는 길로 가지 않게 여기서 붙인다).
        return EditorCommands.adoptingOrphans(document, EditorCommands.finalized(document, edit), folded: folded)
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
        isPlainTyping = false
        if history.open == nil, !isReplayingUndo, !isApplyingEdit { selectionBeforeEdit = textView.selectedRange() }
        // 원문이 바뀌는 모든 길목이다. 접혀서 보이지 않는 줄에 닿는 편집은 넣지 않고 그 토글을 편다.
        // 무엇이 바뀌는지 본 뒤에 다시 하게 한다. 되돌리기는 막지 않는다(접힘이 함께 돌아온다).
        if !allowsHiddenEdit, !isReplayingUndo {
            let broken = FoldState.brokenRoots(by: clamped(range), in: document, folded: folded)
            if !broken.isEmpty {
                setFolded(folded.subtracting(broken), notify: true)
                return false
            }
        }
        guard !isApplyingEdit, !isReplayingUndo else { return true }
        // 조합 중에는 원문을 따로 고치지 않는다. 보이지 않는 ``` 줄의 한쪽만 지워지는 편집만 막는다.
        if textView.hasMarkedText() {
            guard EditorCommands.breaksCodeFence(document, clamped(range)) else { return true }
            onRejectedEdit()
            return false
        }
        let original = clamped(range)
        let text = LineEndings.normalized(replacementString)
        let swallows = swallowsCodeTriggerKey
        swallowsCodeTriggerKey = false
        let tag = codeTag
        codeTag = nil
        let absorb = absorbRun
        absorbRun = nil
        // 편집의 경계를 감춘 글자(줄 머리, 백슬래시) 밖으로 옮긴다.
        let range = EditorCommands.normalized(document, original, replacement: text)
        // 보이지 않는 ``` 줄의 한쪽만 지워지는 편집은 넣지 않는다(편집 명령은 스스로 맞춰 쓴다).
        if EditorCommands.breaksCodeFence(document, range) {
            onRejectedEdit()
            return false
        }

        if range.length == 0, !text.isEmpty {
            // 바깥이 줄바꿈 없이 붙인 줄의 끝에 커서가 있다. 이어 치는 글은 새 줄에서 시작한다.
            if !text.hasPrefix("\n"), takePendingLineBreak(at: range.location) {
                apply(.insert("\n" + text, replacing: range))
                return false
            }
            // 세 번째 백틱으로 코드 블록이 이미 만들어졌다. 이어 누른 Space는 넣지 않는다.
            if swallows, text == " " { return false }
            // 줄이 없는 코드 블록의 커서 자리: 친 글이 코드 줄이 된다.
            if let block = EditorCommands.emptyBlock(document, caretAt: range.location) {
                apply(EditorCommands.insertingIntoEmptyBlock(document, block, text))
                return false
            }
            // 정해 둔 서식이 있으면 기호 쌍과 함께 넣는다(한 번의 편집). 여러 줄이면 줄마다 감싼다.
            if let marks = currentTypingMarks() {
                typingMarks = nil
                if !text.contains("\n"), text.allSatisfy(\.isWhitespace) {
                    // 공백은 서식 없이 넣고, 서식은 그다음 글자까지 살려 둔다(기호 바로 뒤는 공백일 수 없다).
                    apply(finalized(.insert(text, replacing: range)))
                    typingMarks = (textView.selectedRange().location, documentVersion, marks)
                    return false
                }
                if let edit = EditorCommands.typing(document, text, caret: range.location, marks: marks) {
                    apply(finalized(edit))
                    return false
                }
            }
            // 구간 끝에서 친 공백 뒤에 글자를 이어 친다: 공백과 함께 구간 안으로 들인다.
            if let absorb, absorb.location == range.location, absorb.version == documentVersion,
               !text.contains("\n"), !text.allSatisfy(\.isWhitespace),
               let edit = EditorCommands.absorbingIntoRun(document, closeStart: absorb.closeStart, caret: range.location, text: text) {
                apply(edit)
                return false
            }
            // 줄 맨 앞의 기호 뒤 Space, 세 번째 백틱: 줄의 종류를 바꾼다.
            if text == " ", let edit = EditorCommands.spaceTrigger(document, selection: range) {
                apply(edit)
                return false
            }
            if text == "`", let edit = EditorCommands.codeBlockTrigger(document, selection: range) {
                let index = document.lineIndex(at: range.location)
                let created = !document.lines[index].kind.isCode
                apply(edit)
                if created {
                    swallowsCodeTriggerKey = true
                    codeTag = (index, documentVersion, "")
                }
                return false
            }
            // 링크 글자 안의 `]`는 백슬래시로 막아 넣는다.
            if text == "]", EditorCommands.isInsideLinkText(document, at: range.location) {
                apply(.insert("\\]", replacing: range))
                return false
            }
            // 닫는 기호를 쳐서 그 자리에서 서식이 된다. 되돌리면 친 기호가 글자로 남도록 두 단계로 넣는다.
            if let conversion = EditorCommands.conversion(document, typing: text, at: range.location) {
                // 바깥에는 서식이 된 마지막 원문만 한 번 알린다.
                guard let formatted = conversion.formatted else {
                    // 영문자나 숫자 바로 뒤에서 연 기호는 글자로 친 것으로 본다. 서식으로 바꾸지 않는다.
                    apply(conversion.literal)
                    return false
                }
                holdsChangeNotification = true
                apply(conversion.literal)
                splitUndoRecord()
                holdsChangeNotification = false
                apply(formatted, isIntermediate: true)
                return false
            }
        }
        // 감춘 기호가 짝을 잃지 않게 고쳐 쓴다(선택을 지우거나 덮어쓸 때, 구간 안에 여러 줄을 넣을 때).
        let wasAtRunEnd = range.length == 0 && document.line(at: range.location).marker(startingAt: range.location)?.isOpen == false
        guard var edit = finalized(EditorCommands.replacing(document, range, with: text) ?? .insert(text, replacing: range)) else {
            return false
        }
        // 새로 생기는 ``` 줄은 글자로 막아 넣는다. 막을 수 없으면 넣지 않고 알린다.
        if !EditorCommands.keepsFencesBalanced(document, edit) {
            guard let repaired = EditorCommands.escapingNewFences(document, edit) else {
                onRejectedEdit()
                return false
            }
            edit = repaired
        }
        guard !EditorCommands.exposesHiddenMarkers(document, edit) else {
            onRejectedEdit()
            return false
        }
        let isSpace = range.length == 0 && !text.isEmpty && text.allSatisfy { $0 == " " || $0 == "\t" }
        let plain = TextEdit.insert(replacementString, replacing: original)
        guard edit.range == plain.range, edit.replacement == plain.replacement, edit.selection == plain.selection else {
            apply(edit)
            // 구간 끝에서 친 공백이 기호 밖으로 나갔다. 이어 치는 글자는 구간에 붙는다.
            if isSpace, wasAtRunEnd { armAbsorb() }
            return false
        }
        // 그대로 넣는다. 이어지는 상태를 넘겨 둔다.
        if isSpace, let absorb, absorb.location == range.location, absorb.version == documentVersion {
            absorbRun = (absorb.closeStart, range.location + text.utf16.count, documentVersion + 1)
        }
        if let tag, range.length == 0, EditorCommands.isLanguageTag(text), tag.openLine + 1 < document.lines.count {
            // 블록을 만든 바로 뒤에 그 첫 줄에 이어 치는 낱말은 언어 이름일 수 있다(Return을 누를 때 정한다).
            let first = document.lines[tag.openLine + 1]
            let typed = document.string(in: NSRange(location: first.start + first.indentLength, length: first.end - first.start - first.indentLength))
            if first.kind == .code, range.location == first.end, typed == tag.typed {
                codeTag = (tag.openLine, documentVersion + 1, tag.typed + text)
            }
        }
        isPlainTyping = true
        return true
    }

    /// 커서 앞이 [닫는 기호들][공백]이면, 이어 치는 글자를 그 구간에 붙이도록 적어 둔다.
    private func armAbsorb() {
        let caret = textView.selectedRange()
        guard caret.length == 0 else { return }
        let line = document.line(at: caret.location)
        var spaceStart = caret.location
        while spaceStart > line.contentStart, InlineParser.isWhitespace(document.units[spaceStart - 1]) { spaceStart -= 1 }
        let closeStart = line.visualStart(from: spaceStart)
        guard spaceStart < caret.location, closeStart < spaceStart, line.marker(endingAt: spaceStart)?.isOpen == false else { return }
        absorbRun = (closeStart, caret.location, documentVersion)
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
        defer { onFormattingChange?() }
        guard !isSettingText else { return }
        if !isApplyingEdit {
            unfoldAroundSelection()
            swallowsCodeTriggerKey = false
            // 커서를 옮기면 정해 둔 "다음에 칠 글자의 서식"은 사라진다(제자리로 돌아와도).
            typingMarks = nil
            if let absorb = absorbRun, absorb.location != textView.selectedRange().location { absorbRun = nil }
            if !isApplyingOutsideChange { pendingLineBreak = nil }
        }
        selectionVersion = documentVersion
        refreshStyling()
        updateDateSuggestion()
    }

    func textDidChange(_ notification: Notification) {
        flushPendingChange()
    }
}
