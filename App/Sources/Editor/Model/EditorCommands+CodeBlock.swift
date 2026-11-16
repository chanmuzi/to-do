import Foundation

// 코드 블록의 ``` 줄은 보이지 않고 커서도 놓이지 않는다. 블록이 문서의 맨 끝이나 맨 앞에 있으면
// 그 너머로 갈 줄이 없으므로, 화살표로 나갈 때 빈 문단을 만들어 준다.

nonisolated extension EditorCommands {
    /// ↓. 커서가 문서 끝에 있는 코드 블록의 마지막 줄이면 블록 아래에 빈 문단을 만들고 그리로 간다.
    /// 닫히지 않은 블록은 닫는 줄도 넣는다. 해당하지 않으면 `nil`.
    static func leaveCodeBlockDownward(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        guard line.kind == .code, let block = line.codeBlock, block.upperBound == doc.lines.count - 1,
              block.last(where: { doc.lines[$0].kind == .code }) == index else { return nil }
        let last = doc.lines[block.upperBound]
        let indent = doc.string(in: doc.lines[block.lowerBound].indentRange)
        let text = last.kind == .fenceClose ? "\n" + indent : "\n" + indent + "```\n" + indent
        return TextEdit(
            range: NSRange(location: last.end, length: 0),
            replacement: text,
            selection: NSRange(location: last.end + text.utf16.count, length: 0)
        )
    }

    /// ↑. 커서가 문서 맨 앞에 있는 코드 블록의 첫 줄이면 블록 위에 빈 문단을 만들고 그리로 간다.
    static func leaveCodeBlockUpward(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let index = doc.lineIndex(at: selection.location)
        let line = doc.lines[index]
        guard line.kind == .code, let block = line.codeBlock, block.lowerBound == 0, index == 1 else { return nil }
        return TextEdit(range: NSRange(location: 0, length: 0), replacement: "\n", selection: NSRange(location: 0, length: 0))
    }
}
