import AppKit
import DateTime
import Models
import Theme

extension EditorController {
    func pruneDateEffects() {
        let ids = Set((history.undoStack + history.redoStack + (history.open.map { [$0] } ?? [])).compactMap(\.dateEffect))
        for (id, effect) in dateEffects where !ids.contains(id) { effect.onUndoUnavailable?() }
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
        let rows = document.blockLines(at: document.lineIndex(at: selection.location))
        if configuration.recognizesDates, onAcceptDate != nil, (isActive || forcesActiveAppearance), !textView.hasMarkedText(),
           !isEndingComposition, !isReplayingUndo, !isSettingText, !isApplyingOutsideChange,
           blockSelection == nil, selection.length == 0, deferredOutsideEdit == nil,
           dismissedDateLines[rows.lowerBound] == nil {
            let index = rows.lowerBound
            let line = document.lines[index]
            if !line.kind.isCode, selection.location >= line.contentStart {
                var excluded: [NSRange] = []
                let end = document.lines[rows.upperBound].contentEnd
                let range = NSRange(location: line.contentStart, length: end - line.contentStart)
                let text = NSMutableString(string: document.string(in: range))
                for i in rows.dropFirst() {
                    let start = document.lines[i - 1].contentEnd
                    let gap = NSRange(location: start - line.contentStart, length: document.lines[i].contentStart - start)
                    text.replaceCharacters(in: gap, with: String(repeating: " ", count: gap.length))
                }
                for span in document.lines[rows].flatMap(\.spans) {
                    switch span.kind {
                    case .code: excluded.append(span.range)
                    case .link where span.openMarker.length == 0: excluded.append(span.range)
                    default: excluded += [span.openMarker, span.closeMarker].filter { $0.length > 0 }
                    }
                }
                let local = excluded.map { NSRange(location: $0.location - line.contentStart, length: $0.length) }
                dateSuggestion = InlineDateProposal.find(in: text as String,
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
                    guard document.lines.indices.contains(index) else { continue }
                    let rows = document.blockLines(at: index)
                    invalidate(lines: rows.lowerBound..<(rows.upperBound + 1))
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
        let index = document.blockLines(at: document.lineIndex(at: selectedRange.location)).lowerBound
        dismissedDateLines[index] = document.blockSource(at: index)
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
                if document.blockSource(at: next) == source { moved[next] = source }
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
        let rows = old.blockLines(at: old.lineIndex(at: selectedRange.location))
        let index = rows.lowerBound
        let line = old.lines[index]
        var planned = old
        var caret = selectedRange.location
        let ranges = proposal.expression.ranges.flatMap { local in
            let match = NSRange(location: line.contentStart + local.location, length: local.length)
            return rows.map { NSIntersectionRange(match, old.lines[$0].contentRange) }.filter { $0.length > 0 }
        }
        for range in ranges.reversed() {
            let expressionLine = planned.lineIndex(at: range.location)
            let edit = EditorCommands.finalized(planned, EditorCommands.insert(planned, "", replacing: range))
            guard EditorCommands.keepsFencesBalanced(planned, edit), !EditorCommands.exposesHiddenMarkers(planned, edit) else {
                onRejectedEdit(); return true
            }
            caret = InlineDateProposal.caret(caret, replacing: edit.range, withLength: edit.replacement.utf16.count)
            planned = MarkdownDocument(edit.applied(to: planned.text))
            // 삭제 접점의 공백만 정리한다. 다른 곳의 정렬용 공백, 인라인 코드는 보존한다.
            let currentLine = planned.lines[expressionLine]
            var lower = min(max(edit.selection.location, currentLine.contentStart), currentLine.contentEnd)
            var upper = lower
            while lower > currentLine.contentStart, InlineParser.isWhitespace(planned.units[lower - 1]) { lower -= 1 }
            while upper < currentLine.contentEnd, InlineParser.isWhitespace(planned.units[upper]) { upper += 1 }
            if upper > lower {
                let space = lower > currentLine.contentStart && upper < currentLine.contentEnd ? " " : ""
                let cleanup = EditorCommands.finalized(planned, EditorCommands.insert(planned, space,
                    replacing: NSRange(location: lower, length: upper - lower)))
                guard !EditorCommands.exposesHiddenMarkers(planned, cleanup) else { onRejectedEdit(); return true }
                caret = InlineDateProposal.caret(caret, replacing: cleanup.range, withLength: cleanup.replacement.utf16.count)
                planned = MarkdownDocument(cleanup.applied(to: planned.text))
            }
        }
        guard let diff = OutsideEdit(from: old.text, to: planned.text) else { return true }
        let source = planned.blockSource(at: index)
        let request = InlineDateAcceptance(item: proposal.item,
            source: InlineScheduleSource(line: index, text: source), todo: TodoAnchor(line: index, sourceLine: source),
            previousText: old.text, nextText: planned.text)
        closeUndoRecord()
        let effect: InlineDateEffect
        do { effect = try accept(request) }
        catch { onDateError(error); onRejectedEdit(); return true }
        let edit = TextEdit(range: diff.range, replacement: diff.replacement,
            selection: NSRange(location: min(caret, planned.length), length: 0),
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
