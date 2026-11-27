import AppKit
import Theme

extension NSPasteboard.PasteboardType {
    /// 앱 안에서 붙여 넣을 때 쓰는 원문 그대로의 조각(형광펜 색 번호, 토글 기호를 잃지 않는다).
    static let floatingNotesMarkdown = NSPasteboard.PasteboardType("local.floating-notes.markdown-source")
}

extension EditorController {
    /// 선택을 복사한다(D-009). 표준 Markdown 글자, HTML, 그리고 앱 안에서 쓰는 원문 조각을 함께 올린다.
    /// - Returns: 복사할 것이 없으면 `false`.
    @discardableResult
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        let selection = clamped(textView.selectedRange())
        let export: CopyExport
        if let blocks = blockSelection {
            let rows = selectedBlockRows(blocks, includingChildren: true)
            export = CopyExport(source: document.string(in: document.sourceRange(for: rows)))
        } else {
            guard selection.length > 0 else { return false }
            export = CopyExport(document, selection: selection)
        }
        pasteboard.clearContents()
        let markdown = NSPasteboard.PasteboardType("net.daringfireball.markdown")
        pasteboard.declareTypes([.string, .html, markdown, .floatingNotesMarkdown], owner: nil)
        pasteboard.setString(export.markdown, forType: .string)
        pasteboard.setString(export.markdown, forType: markdown)
        pasteboard.setString(export.html(highlightColors: highlightCSSColors), forType: .html)
        pasteboard.setString(export.source, forType: .floatingNotesMarkdown)
        return true
    }

    /// 붙여 넣는다. Float 원문, 인식한 Notion HTML, 일반 글자, URL 순으로 읽는다.
    /// 줄바꿈은 `\n`으로 맞춘다.
    func paste(from pasteboard: NSPasteboard, inside: Bool = false) {
        guard let text = Self.source(from: pasteboard), !text.isEmpty else { return }
        pasteSource(LineEndings.normalized(text), inside: inside)
    }

    static func source(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: .floatingNotesMarkdown)
            ?? pasteboard.string(forType: .html).flatMap(NotionHTMLImport.source)
            ?? pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: .URL)
    }

    func pasteSource(_ text: String, inside: Bool = false) {
        guard !text.isEmpty, textView.isEditable else { return }
        if let blocks = blockSelection, !textView.hasMarkedText() {
            let end = selectedBlockRows(blocks, includingChildren: true).upperBound
            let plan = EditorCommands.blockPaste(document, text: text, target: blocks.rows.upperBound, belowRow: end,
                                                 inside: inside, folded: folded)
            if let plan, let first = plan.roots.first, let last = plan.roots.last {
                splitUndoRecord()
                let version = documentVersion
                apply(plan.edit)
                if version != documentVersion { showBlocks(BlockSelection(anchor: first, focus: last, pastedRoots: plan.roots)) }
                closeUndoRecord()
            }
            return
        }
        guard !inside else { return }
        guard !textView.hasMarkedText() else {
            textView.insertText(text, replacementRange: textView.selectedRange())
            return
        }
        let selection = clamped(textView.selectedRange())
        if let plan = EditorCommands.pasteAtParentEnd(document, text: text, selection: selection, folded: foldsAtCaret(selection)) {
            var edit = plan.edit
            edit.selection.location = edit.range.location + edit.replacement.utf16.count
            apply(edit)
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
        let prepared = EditorCommands.preparedForPaste(document, text, replacing: selection, runEnd: continuingRunEnd)
        guard !prepared.isEmpty else { return }
        textView.insertText(prepared, replacementRange: selection)
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
