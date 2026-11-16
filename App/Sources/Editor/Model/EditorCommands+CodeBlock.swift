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

    // MARK: 줄이 없는 블록

    // 여는 줄 바로 다음이 닫는 줄인 블록(다른 프로그램이 쓴 파일, 또는 ``` 만 있고 끝난 문서)에는 코드 줄이
    // 없다. 그래도 들어가서 쓸 수 있도록 커서가 놓일 자리 하나를 둔다: 닫는 줄의 맨 앞(닫는 줄이 없으면
    // 여는 줄의 끝). 화면에서는 그 줄이 빈 코드 줄로 보이고, 거기서 친 글은 새 코드 줄이 된다.

    /// 그 줄이 속한 블록에 코드 줄이 하나도 없으면 그 블록.
    static func emptyBlock(_ doc: MarkdownDocument, at index: Int) -> ClosedRange<Int>? {
        guard let block = doc.lines[index].codeBlock, !block.contains(where: { doc.lines[$0].kind == .code }) else { return nil }
        return block
    }

    /// 줄이 없는 블록에서 커서가 놓이는 자리.
    static func emptyBlockCaret(_ doc: MarkdownDocument, _ block: ClosedRange<Int>) -> Int {
        let last = doc.lines[block.upperBound]
        return last.kind == .fenceClose ? last.start + last.indentLength : last.end
    }

    /// 그 위치가 줄이 없는 블록의 커서 자리면 그 블록.
    static func emptyBlock(_ doc: MarkdownDocument, caretAt position: Int) -> ClosedRange<Int>? {
        guard let block = emptyBlock(doc, at: doc.lineIndex(at: position)), emptyBlockCaret(doc, block) == position else { return nil }
        return block
    }

    /// 줄이 없는 블록의 커서 자리에 `text`를 넣는다: 그 글이 블록의 코드 줄이 된다.
    static func insertingIntoEmptyBlock(_ doc: MarkdownDocument, _ block: ClosedRange<Int>, _ text: String) -> TextEdit {
        let last = doc.lines[block.upperBound]
        let indent = doc.string(in: doc.lines[block.lowerBound].indentRange)
        let body = text.components(separatedBy: "\n").map { indent + $0 }.joined(separator: "\n")
        if last.kind == .fenceClose {
            return TextEdit(
                range: NSRange(location: last.start, length: 0),
                replacement: body + "\n",
                selection: NSRange(location: last.start + body.utf16.count, length: 0)
            )
        }
        return TextEdit(
            range: NSRange(location: last.end, length: 0),
            replacement: "\n" + body,
            selection: NSRange(location: last.end + 1 + body.utf16.count, length: 0)
        )
    }

    /// 블록을 통째로 지운다(앞이나 뒤의 줄바꿈 하나와 함께). 커서는 `caret`이 지운 뒤에 놓일 곳으로 간다.
    static func removingBlock(_ doc: MarkdownDocument, _ block: ClosedRange<Int>) -> TextEdit {
        let open = doc.lines[block.lowerBound]
        let last = doc.lines[block.upperBound]
        if block.upperBound + 1 < doc.lines.count {
            // 뒤의 줄바꿈까지 지운다. 커서는 그다음 줄의 글자 맨 앞.
            let next = doc.lines[block.upperBound + 1]
            return TextEdit(
                range: NSRange(location: open.start, length: next.start - open.start),
                replacement: "",
                selection: NSRange(location: open.start + (next.caretStart - next.start), length: 0)
            )
        }
        if block.lowerBound > 0 {
            let previous = doc.lines[block.lowerBound - 1]
            return TextEdit(
                range: NSRange(location: previous.end, length: last.end - previous.end),
                replacement: "",
                selection: NSRange(location: previous.end, length: 0)
            )
        }
        return TextEdit(range: NSRange(location: 0, length: doc.length), replacement: "", selection: NSRange(location: 0, length: 0))
    }
}
