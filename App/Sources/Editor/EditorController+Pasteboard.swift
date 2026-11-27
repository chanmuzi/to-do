import AppKit
import Theme

extension NSPasteboard.PasteboardType {
    static let chromiumWebCustomData = NSPasteboard.PasteboardType("org.chromium.web-custom-data")

    static let floatingNotesFoldState = NSPasteboard.PasteboardType("local.floating-notes.fold-state")

    /// 앱 안에서 붙여 넣을 때 쓰는 원문 그대로의 조각(형광펜 색 번호, 토글 기호를 잃지 않는다).
    static let floatingNotesMarkdown = NSPasteboard.PasteboardType("local.floating-notes.markdown-source")
}

extension EditorController {
    /// 선택을 복사한다(D-009). 표준 Markdown 글자, HTML, Notion 블록과 Float 원문을 함께 올린다.
    /// - Returns: 복사할 것이 없으면 `false`.
    @discardableResult
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        let selection = clamped(textView.selectedRange())
        let export: CopyExport
        let firstRow: Int
        if let blocks = blockSelection {
            let rows = selectedBlockRows(blocks, includingChildren: true)
            firstRow = rows.lowerBound
            export = CopyExport(source: document.string(in: document.sourceRange(for: rows)))
        } else {
            guard selection.length > 0 else { return false }
            firstRow = document.lineIndex(at: selection.location)
            export = CopyExport(document, selection: selection)
        }
        pasteboard.clearContents()
        let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
        let customData = export.chromiumData
        var types: [NSPasteboard.PasteboardType] = [.string, .html, markdown, .floatingNotesMarkdown]
        let folds = export.copiedFolds(in: document, from: firstRow, state: foldState)
        let foldData = try? JSONEncoder().encode(folds)
        if foldData != nil { types.append(.floatingNotesFoldState) }
        if customData != nil { types.append(.chromiumWebCustomData) }
        pasteboard.declareTypes(types, owner: nil)
        if let foldData { pasteboard.setData(foldData, forType: .floatingNotesFoldState) }
        if let customData { pasteboard.setData(customData, forType: .chromiumWebCustomData) }
        pasteboard.setString(export.markdown, forType: .string)
        pasteboard.setString(export.markdown, forType: markdown)
        pasteboard.setString(export.html(highlightColors: highlightCSSColors), forType: .html)
        pasteboard.setString(export.source, forType: .floatingNotesMarkdown)
        return true
    }

    /// 붙여 넣는다. Float 원문, Notion 블록, 인식한 HTML, 일반 글자, URL 순으로 읽는다.
    /// 줄바꿈은 `\n`으로 맞춘다.
    func paste(from pasteboard: NSPasteboard, inside: Bool = false) {
        guard let source = Self.source(from: pasteboard) else { return }
        pasteSource(source, inside: inside)
    }

    static func source(from pasteboard: NSPasteboard) -> PasteSource? {
        if let text = pasteboard.string(forType: .floatingNotesMarkdown) {
            let normalized = LineEndings.normalized(text)
            guard let data = pasteboard.data(forType: .floatingNotesFoldState),
                  let state = try? JSONDecoder().decode(FoldState.self, from: data) else { return PasteSource(normalized) }
            return PasteSource(normalized, toggles: .keep(state))
        }
        if let text = pasteboard.data(forType: .chromiumWebCustomData).flatMap(NotionBlocksImport.source(from:))
            ?? pasteboard.string(forType: .html).flatMap(NotionHTMLImport.source) {
            return PasteSource(LineEndings.normalized(text), toggles: .closeAll)
        }
        return (pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)).map { PasteSource(LineEndings.normalized($0)) }
    }

    func pasteSource(_ text: String, inside: Bool = false) {
        pasteSource(PasteSource(text), inside: inside)
    }

    private func pasteSource(_ source: PasteSource, inside: Bool) {
        let text = source.text
        guard !text.isEmpty, textView.isEditable else { return }
        let groupsPaste = blockSelection != nil || !source.closedByRow.isEmpty
        if groupsPaste { splitUndoRecord() }
        defer { if groupsPaste { closeUndoRecord() } }
        if let blocks = blockSelection, !textView.hasMarkedText() {
            let end = selectedBlockRows(blocks, includingChildren: true).upperBound
            let plan = EditorCommands.blockPaste(document, text: text, target: blocks.rows.upperBound, belowRow: end,
                                                 inside: inside, folded: folded)
            if let plan, let first = plan.roots.first, let last = plan.roots.last {
                let version = documentVersion
                applyBlockPaste(plan.edit, source: source)
                if version != documentVersion { showBlocks(BlockSelection(anchor: first, focus: last, pastedRoots: plan.roots)) }
            }
            return
        }
        guard !inside else { return }
        guard !textView.hasMarkedText() else {
            insertPastedText(source, replacing: clamped(textView.selectedRange()))
            return
        }
        let selection = clamped(textView.selectedRange())
        if let plan = EditorCommands.pasteAtParentEnd(document, text: text, selection: selection, folded: foldsAtCaret(selection)) {
            var edit = plan.edit
            edit.selection.location = edit.range.location + edit.replacement.utf16.count
            applyBlockPaste(edit, source: source)
            return
        }
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.length > 0, !address.contains(where: \.isWhitespace), LinkPolicy.openableURL(address) != nil {
            let line = document.line(at: selection.location)
            let pastesLiterally = line.kind.isCode || line.spans.contains { span in
                guard span.contains(selection) else { return false }
                switch span.kind { case .code, .link: return true; default: return false }
            }
            if !pastesLiterally {
                guard case .new(let range) = currentLinkTarget,
                      let edit = EditorCommands.setLink(document, target: .new(range), address: address)
                else { explainRejectedLink(linkSelectionHelp); return }
                apply(edit)
                return
            }
        }
        let prepared = EditorCommands.preparedForPaste(document, source, replacing: selection, runEnd: continuingRunEnd)
        guard !prepared.text.isEmpty else { return }
        insertPastedText(prepared, replacing: selection)
    }

    private func applyBlockPaste(_ edit: TextEdit, source: PasteSource) {
        withPastedFolds(source, firstRow: { self.document.lineIndex(at: edit.range.location + 1) }) {
            apply(edit)
        }
    }

    private func insertPastedText(_ source: PasteSource, replacing selection: NSRange) {
        guard !source.closedByRow.isEmpty else {
            textView.insertText(source.text, replacementRange: selection)
            return
        }
        let rowsBelow = document.lines.count - 1 - document.lineIndex(at: NSMaxRange(selection))
        let breaks = source.text.utf8.count(where: { $0 == 10 })
        let start = EditorCommands.normalized(document, selection, replacement: source.text).location
        // 기존 뒷줄과 조각의 줄 수를 끝에서 빼면, 앞에 개행이 추가되거나 뒤의 들여쓰기가 바뀌어도 맞는다.
        withPastedFolds(source, firstRow: { self.document.lines.count - 1 - rowsBelow - breaks }, start: start) {
            textView.insertText(source.text, replacementRange: selection)
        }
    }

    private func withPastedFolds(_ source: PasteSource, firstRow: () -> Int, start: Int = 0, edit: () -> Void) {
        guard !source.closedByRow.isEmpty else { edit(); return }
        let version = documentVersion
        let before = foldState
        let selection = selectedRange
        let wasHolding = holdsChangeNotification
        holdsChangeNotification = true
        defer {
            holdsChangeNotification = wasHolding
            flushPendingChange()
        }
        edit()
        guard version != documentVersion else { return }
        source.applyFolds(to: &foldState, in: document, firstRow: firstRow(), insertionStart: start)
        editSetFoldsExplicitly = true
        if before != foldState, history.open == nil, let last = lastBodyEdit {
            // 같은 원문으로 덮어쓰고 접힘만 바뀐 경우에도 그 범위를 한 단계로 기록한다.
            let previous = (last.previous as NSString).substring(with: last.range)
            history.open = UndoRecord(edits: [UndoEdit(location: last.range.location, old: previous, new: previous)],
                                      selectionBefore: selection, selectionAfter: selectedRange)
        }
        history.open?.isTyping = false
        let caret = clamped(selectedRange)
        let visible = CaretSnapping.snap(old: caret, new: caret, in: document, folded: folded, textChanged: true)
        if visible != caret {
            setSelection(visible)
            textView.scrollRangeToVisible(visible)
        }
    }

    /// 다른 앱에 붙일 HTML의 글자색과 바탕색. 받는 쪽 바탕을 알 수 없으므로 라이트 값을 쓴다.
    var highlightCSSColors: [Int: String] {
        Dictionary(uniqueKeysWithValues: InkColor.palette.map { color in
            (color.id, Self.css(theme.tokens.color(color.token, .light)))
        })
    }

    static func css(_ color: RGBA) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        if color.alpha >= 1 {
            return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
        }
        return "rgba(\(byte(color.red)),\(byte(color.green)),\(byte(color.blue)),\(color.alpha))"
    }
}
