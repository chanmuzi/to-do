import Foundation

// ``` 줄의 짝. ``` 줄은 보이지 않아서, 짝을 잃으면 그 아래의 글이 모두 코드로 뒤집히고 사용자는 까닭을 볼 수
// 없다. 그런 편집은 고쳐서 넣거나(새로 생기는 ``` 를 글자로 막는다) 넣지 않는다.

nonisolated extension EditorCommands {
    /// 닫는 줄이 없는 코드 블록이 있는지.
    static func hasUnterminatedFence(_ doc: MarkdownDocument) -> Bool {
        guard let last = doc.lines.last, let block = last.codeBlock else { return false }
        return last.kind != .fenceClose || block.lowerBound == block.upperBound
    }

    /// 그 편집을 넣어도 ``` 줄의 짝이 맞는지. 닫히지 않은 블록이 새로 생기는 편집은 넣지 않는다
    /// (``` 줄은 보이지 않아서, 짝을 잃으면 그 아래의 글이 모두 코드로 뒤집히고 사용자는 까닭을 볼 수 없다).
    /// 이미 닫히지 않은 블록이 있는 문서(다른 프로그램이 쓴 파일)에서는 막지 않는다.
    static func keepsFencesBalanced(_ doc: MarkdownDocument, _ edit: TextEdit) -> Bool {
        let lines = doc.lineIndex(at: edit.range.location)...doc.lineIndex(at: NSMaxRange(edit.range))
        let backtick: unichar = 0x60
        let touchesBacktick = edit.replacement.utf16.contains(backtick) || lines.contains { index in
            let line = doc.lines[index]
            return line.kind.isCode || (line.start..<line.end).contains { doc.units[$0] == backtick }
        }
        guard touchesBacktick, !hasUnterminatedFence(doc) else { return true }
        return !hasUnterminatedFence(MarkdownDocument(edit.applied(to: doc.text)))
    }

    /// 짝을 잃게 하는 편집을 고쳐 쓴다: 편집으로 새로 생기는 ``` 줄(글자로 보이던 백틱이 줄 머리에 놓이게 된
    /// 것. `a``` `에서 `a`를 지움, `x ``` y`에서 `x `를 지움)의 첫 백틱을 백슬래시로 막아 글자로 남긴다. 화면에는
    /// 편집 전에 보이던 백틱이 그대로 보인다. 고칠 수 없으면 `nil`:
    /// - 코드 블록 안의 편집(그 안에서는 백슬래시도 글자여서 막을 수 없다).
    /// - 이미 있던 ``` 줄을 건드리는 편집.
    /// - 여러 줄을 넣으며 ``` 줄을 들여오는 편집(어느 줄이 블록의 끝인지 정할 수 없다).
    static func escapingNewFences(_ doc: MarkdownDocument, _ edit: TextEdit) -> TextEdit? {
        let first = doc.line(at: edit.range.location)
        let last = doc.line(at: NSMaxRange(edit.range))
        guard !first.kind.isCode, !last.kind.isCode,
              !(edit.replacement.contains("\n") && edit.replacement.contains("```")) else { return nil }
        let lineRange = NSRange(location: first.start, length: last.end - first.start)
        let local = NSRange(location: edit.range.location - first.start, length: edit.range.length)
        let rebuilt = (doc.string(in: lineRange) as NSString).replacingCharacters(in: local, with: edit.replacement)
        var units = Array(rebuilt.utf16)
        var selection = edit.selection
        var changed = false
        var lineStart = 0
        while lineStart <= units.count {
            let lineEnd = units[lineStart...].firstIndex(of: 0x0A) ?? units.count
            let indent = LineClassifier.indent(units, from: lineStart, to: lineEnd).length
            if LineClassifier.isFence(units, from: lineStart + indent, to: lineEnd) {
                let at = lineStart + indent
                units.insert(0x5C, at: at)
                // 막은 글자의 앞은 백슬래시의 앞이다. 그 뒤의 위치만 한 칸 민다.
                func move(_ position: Int) -> Int { position > lineRange.location + at ? position + 1 : position }
                let start = move(selection.location)
                selection = NSRange(location: start, length: move(NSMaxRange(selection)) - start)
                changed = true
                lineStart = lineEnd + 2
            } else {
                lineStart = lineEnd + 1
            }
        }
        guard changed else { return nil }
        var result = edit
        result.range = lineRange
        result.replacement = String(utf16CodeUnits: units, count: units.count)
        result.selection = selection
        return keepsFencesBalanced(doc, result) ? result : nil
    }
}
