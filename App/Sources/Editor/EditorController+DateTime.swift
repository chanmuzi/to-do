import AppKit
import DateTime
import Models
import Theme

extension EditorController {
    func pruneDateEffects() {
        let ids = Set((history.undoStack + history.redoStack + (history.open.map { [$0] } ?? [])).compactMap(\.dateEffect))
        dateEffects = dateEffects.filter { ids.contains($0.key) }
    }

    func updateDateSuggestion() {
        guard !isRestyling, !isUpdatingDateSuggestion else { return }
        isUpdatingDateSuggestion = true
        defer { isUpdatingDateSuggestion = false }
        let old = dateSuggestion
        let oldLine = dateSuggestionLine
        let oldLineCount = dateSuggestionLineCount
        let oldAbove = dateSuggestionAbove
        dateSuggestion = nil
        dateSuggestionLine = nil
        let selection = selectedRange
        if onAcceptDate != nil, (isActive || forcesActiveAppearance), !textView.hasMarkedText(),
           !isEndingComposition, !isReplayingUndo, !isSettingText, !isApplyingOutsideChange,
           selection.length == 0, deferredOutsideEdit == nil,
           !(dismissedDate?.text == text && dismissedDate?.selection == selection) {
            let index = document.lineIndex(at: selection.location)
            let line = document.lines[index]
            if !line.kind.isCode, selection.location >= line.contentStart {
                var excluded: [NSRange] = []
                for span in line.spans {
                    switch span.kind {
                    case .code: excluded.append(span.range)
                    case .link where span.openMarker.length == 0: excluded.append(span.range)
                    default: excluded += [span.openMarker, span.closeMarker].filter { $0.length > 0 }
                    }
                }
                let local = excluded.map { NSRange(location: $0.location - line.contentStart, length: $0.length) }
                dateSuggestion = InlineDateProposal.find(in: document.string(in: line.contentRange),
                    caret: selection.location - line.contentStart, now: dateNow(), calendar: dateCalendar, excluding: local)
                if dateSuggestion != nil { dateSuggestionLine = index }
            }
        }
        let message = dateSuggestion.map {
            let p = ReminderPresentation(item: $0.item, now: dateNow(), options: NoteDisplayOptions(), calendar: dateCalendar)
            return ($0.item.kind == .event ? "일정 " : "리마인더 ") + (p.text ?? "")
        }
        dateHint.prepare(message)
        let caret = caretRect() ?? .zero
        let right = textView.bounds.width - theme.docPadding.trailing
        // 뒤에 원문(감춘 닫는 기호 포함)이 있으면 그 자리를 사용하지 않는다.
        dateSuggestionAbove = dateSuggestionLine.map {
            selection.location != document.lines[$0].end ||
            caret.maxX + theme.space(.sp2) + dateHint.preferredSize.width > right ||
            dateHint.preferredSize.height > style.body.lineHeight
        } ?? false
        dateSuggestionLineCount = document.lines.count
        if old != dateSuggestion || oldLine != dateSuggestionLine || oldAbove != dateSuggestionAbove ||
            (oldLine != nil && oldLineCount != document.lines.count) {
            if oldLine != nil && oldLineCount != document.lines.count {
                restyleAll()
            } else {
                for index in Set([oldLine, dateSuggestionLine].compactMap { $0 }).sorted() {
                    invalidate(lines: index..<(index + 1))
                }
            }
        }
        layoutDateHint()
        if oldAbove != dateSuggestionAbove || oldLine != dateSuggestionLine { reportContentHeight() }
        textView.setAccessibilityHelp(message)
    }

    /// 텍스트 뷰 안에 놓아 스크롤/클리핑도 본문과 함께 움직인다.
    func layoutDateHint() {
        guard let index = dateSuggestionLine, document.lines.indices.contains(index), let caret = caretRect() else {
            dateHint.hide(); return
        }
        let pad = theme.space(.sp2)
        let right = textView.bounds.width - theme.docPadding.trailing
        if dateSuggestionAbove,
           let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: document.lines[index].start),
           let fragment = layoutManager.textLayoutFragment(for: location) {
            layoutManager.ensureLayout(for: fragment.rangeInElement)
            let origin = textView.textContainerOrigin
            let area = NSRect(x: origin.x, y: origin.y + fragment.layoutFragmentFrame.minY,
                              width: max(0, right - origin.x), height: dateHint.preferredSize.height)
            dateHint.place(in: textView, area: area)
        } else {
            dateHint.place(in: textView, area: NSRect(x: caret.maxX + pad, y: caret.midY - dateHint.preferredSize.height / 2,
                width: max(0, right - caret.maxX - pad), height: dateHint.preferredSize.height))
        }
    }

    @discardableResult func dismissDateSuggestion() -> Bool {
        guard dateSuggestion != nil else { return false }
        dismissedDate = (text, selectedRange)
        updateDateSuggestion()
        return true
    }

    /// 미리 계산한 원문 편집만 실행한다. 실패하면 원문/기록 모두 손대지 않는다.
    func acceptDateSuggestion() -> Bool {
        guard dateSuggestion != nil else { return false }
        updateDateSuggestion()
        guard let proposal = dateSuggestion, let accept = onAcceptDate else { return true }
        let old = document
        let index = old.lineIndex(at: selectedRange.location)
        let line = old.lines[index]
        var planned = old
        for local in proposal.expression.ranges.reversed() {
            let range = NSRange(location: line.contentStart + local.location, length: local.length)
            let edit = EditorCommands.finalized(planned, EditorCommands.insert(planned, "", replacing: range))
            guard EditorCommands.keepsFencesBalanced(planned, edit), !EditorCommands.exposesHiddenMarkers(planned, edit) else {
                onRejectedEdit(); return true
            }
            planned = MarkdownDocument(edit.applied(to: planned.text))
            // 삭제 접점의 공백만 정리한다. 다른 곳의 정렬용 공백·인라인 코드는 보존한다.
            let currentLine = planned.lines[index]
            var lower = min(max(edit.selection.location, currentLine.contentStart), currentLine.end)
            var upper = lower
            while lower > currentLine.contentStart, InlineParser.isWhitespace(planned.units[lower - 1]) { lower -= 1 }
            while upper < currentLine.end, InlineParser.isWhitespace(planned.units[upper]) { upper += 1 }
            if upper > lower {
                let space = lower > currentLine.contentStart && upper < currentLine.end ? " " : ""
                let cleanup = EditorCommands.finalized(planned, EditorCommands.insert(planned, space,
                    replacing: NSRange(location: lower, length: upper - lower)))
                guard !EditorCommands.exposesHiddenMarkers(planned, cleanup) else { onRejectedEdit(); return true }
                planned = MarkdownDocument(cleanup.applied(to: planned.text))
            }
        }
        guard let diff = OutsideEdit(from: old.text, to: planned.text) else { return true }
        let nextLine = planned.lines[index]
        let todo: TodoAnchor?
        if case .todo = nextLine.kind { todo = TodoAnchor(line: index, text: planned.string(in: nextLine.contentRange)) }
        else { todo = nil }
        let request = InlineDateAcceptance(item: proposal.item,
            source: InlineScheduleSource(line: index, text: planned.string(in: nextLine.range)), todo: todo,
            previousText: old.text, nextText: planned.text)
        closeUndoRecord()
        let effect: InlineDateEffect
        do { effect = try accept(request) }
        catch { onDateError(error); onRejectedEdit(); return true }
        let edit = TextEdit(range: diff.range, replacement: diff.replacement,
            selection: NSRange(location: min(diff.range.location + diff.replacement.utf16.count, nextLine.end), length: 0),
            preservesLines: true)
        // 미리 검증한 삭제는 기존 편집 경로에서 한 단계로 기록한다.
        apply(edit)
        guard text == planned.text else {
            do { try effect.undo() } catch { onDateError(error) }
            return true
        }
        let token = UUID()
        dateEffects[token] = effect
        history.open?.dateEffect = token
        closeUndoRecord()
        updateDateSuggestion()
        return true
    }
}
