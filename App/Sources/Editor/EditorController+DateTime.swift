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
        dateSuggestion = nil
        dateSuggestionLine = nil
        moveDateDismissals()
        let selection = selectedRange
        if configuration.recognizesDates, onAcceptDate != nil, (isActive || forcesActiveAppearance), !textView.hasMarkedText(),
           !isEndingComposition, !isReplayingUndo, !isSettingText, !isApplyingOutsideChange,
           selection.length == 0, deferredOutsideEdit == nil,
           dismissedDateLines[document.lineIndex(at: selection.location)] == nil {
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
        dateSuggestionLineCount = document.lines.count
        if old != dateSuggestion || oldLine != dateSuggestionLine ||
            (oldLine != nil && oldLineCount != document.lines.count) {
            if oldLine != nil && oldLineCount != document.lines.count {
                restyleAll()
            } else {
                for index in Set([oldLine, dateSuggestionLine].compactMap { $0 }).sorted() {
                    invalidate(lines: index..<(index + 1))
                }
            }
        }
        textView.setAccessibilityHelp(message)
    }

    func scheduleRemoved(fromBodyLine line: Int) {
        moveDateDismissals()
        dismissedDateLines.removeValue(forKey: line)
        updateDateSuggestion()
    }

    func dismissCurrentDateLine() {
        let index = document.lineIndex(at: selectedRange.location)
        dismissedDateLines[index] = document.string(in: document.lines[index].range)
        dismissedDateDocument = document
    }

    /// 앞줄의 삽입, 삭제는 닫아 둔 줄의 내용 변경이 아니다. 원문 위치를 따라 옮긴다.
    private func moveDateDismissals() {
        if let previous = dismissedDateDocument,
           let edit = OutsideEdit(from: previous.text, to: document.text) {
            var moved: [Int: String] = [:]
            for (index, source) in dismissedDateLines where previous.lines.indices.contains(index) {
                let line = previous.lines[index]
                guard NSIntersectionRange(line.range, edit.range).length == 0 else { continue }
                let start = edit.moved(line.start, sticksToEnd: true)
                let next = document.lineIndex(at: min(start, document.length))
                if document.string(in: document.lines[next].range) == source { moved[next] = source }
            }
            dismissedDateLines = moved
        }
        dismissedDateDocument = dismissedDateLines.isEmpty ? nil : document
    }

    @discardableResult func dismissDateSuggestion() -> Bool {
        guard dateSuggestion != nil else { return false }
        dismissCurrentDateLine()
        updateDateSuggestion()
        return true
    }

    /// 미리 계산한 원문 편집만 실행한다. 실패하면 원문/기록 모두 손대지 않는다.
    func acceptDateSuggestion() -> Bool {
        updateDateSuggestion()
        guard let proposal = dateSuggestion, let accept = onAcceptDate else { return false }
        let old = document
        let index = old.lineIndex(at: selectedRange.location)
        let line = old.lines[index]
        var planned = old
        var caret = selectedRange.location
        for local in proposal.expression.ranges.reversed() {
            let range = NSRange(location: line.contentStart + local.location, length: local.length)
            let edit = EditorCommands.finalized(planned, EditorCommands.insert(planned, "", replacing: range))
            guard EditorCommands.keepsFencesBalanced(planned, edit), !EditorCommands.exposesHiddenMarkers(planned, edit) else {
                onRejectedEdit(); return true
            }
            caret = InlineDateProposal.caret(caret, replacing: edit.range, withLength: edit.replacement.utf16.count)
            planned = MarkdownDocument(edit.applied(to: planned.text))
            // 삭제 접점의 공백만 정리한다. 다른 곳의 정렬용 공백, 인라인 코드는 보존한다.
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
                caret = InlineDateProposal.caret(caret, replacing: cleanup.range, withLength: cleanup.replacement.utf16.count)
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
            selection: NSRange(location: min(caret, nextLine.end), length: 0),
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
