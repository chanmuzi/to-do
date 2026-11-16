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
        guard selection.length > 0 else { return false }
        let export = CopyExport(document, selection: selection)
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .html, .floatingNotesMarkdown], owner: nil)
        pasteboard.setString(export.markdown, forType: .string)
        pasteboard.setString(export.html(highlightColors: highlightCSSColors), forType: .html)
        pasteboard.setString(export.source, forType: .floatingNotesMarkdown)
        return true
    }

    /// 붙여 넣는다. 이 앱에서 복사한 것이면 원문 조각을, 아니면 글자를 그대로 넣는다.
    /// 줄바꿈은 `\n`으로 맞춘다.
    func paste(from pasteboard: NSPasteboard) {
        guard let text = pasteboard.string(forType: .floatingNotesMarkdown) ?? pasteboard.string(forType: .string),
              !text.isEmpty else { return }
        guard !textView.hasMarkedText() else {
            textView.insertText(LineEndings.normalized(text), replacementRange: textView.selectedRange())
            return
        }
        let selection = clamped(textView.selectedRange())
        let runEnd = absorbRun.flatMap { $0.location == selection.location && $0.version == documentVersion ? $0.closeStart : nil }
        let prepared = EditorCommands.preparedForPaste(document, LineEndings.normalized(text), replacing: selection, runEnd: runEnd)
        guard !prepared.isEmpty else { return }
        textView.insertText(prepared, replacementRange: selection)
    }

    /// 다른 앱에 붙였을 때의 형광펜 바탕색. 받는 쪽 바탕을 알 수 없으므로 라이트 값을 쓴다.
    var highlightCSSColors: [Int: String] {
        Dictionary(uniqueKeysWithValues: HighlightColor.allCases.map { color in
            (color.rawValue, Self.css(theme.tokens.color(color.background, .light)))
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
