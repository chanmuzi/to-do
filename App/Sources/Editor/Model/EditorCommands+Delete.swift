import Foundation

/// 키 하나를 어떻게 처리할지.
nonisolated enum KeyOutcome: Equatable, Sendable {
    /// 이 편집을 넣는다.
    case edit(TextEdit)
    /// 원문은 그대로 두고 커서만 옮긴다.
    case select(NSRange)
    /// 아무것도 하지 않는다(텍스트 뷰의 기본 동작도 하지 않는다).
    case ignore
    /// 텍스트 뷰의 기본 동작에 맡긴다.
    case passThrough

    var edit: TextEdit? {
        if case .edit(let edit) = self { edit } else { nil }
    }
}

nonisolated extension EditorCommands {
    /// ⌫ (선택이 없을 때).
    ///
    /// - 글자가 보이기 시작하는 자리에서: 제목, 목록은 줄 머리 기호를 지워 본문으로 바꾸고, 들여 쓴
    ///   본문은 한 단계 내어 쓴다. 그다음 ⌫가 윗줄과 합친다.
    /// - 그 밖에는 보이는 글자 하나를 지운다. 감춘 기호만 지우는 일은 없고, 구간의 보이는 글자가
    ///   모두 지워지면 기호도 함께 지운다.
    /// - 빈 코드 블록의 맨 앞에서는 블록을 없앤다. 코드 블록의 ``` 줄은 지우지 않는다.
    static func deleteBackward(_ doc: MarkdownDocument, selection: NSRange) -> KeyOutcome {
        guard selection.length == 0 else { return .passThrough }
        let position = selection.location
        let index = doc.lineIndex(at: position)
        let line = doc.lines[index]

        if line.kind.isCode {
            // 줄이 없는 블록의 커서 자리: 블록을 없앤다.
            if let block = emptyBlock(doc, caretAt: position) { return .edit(removingBlock(doc, block)) }
            guard line.kind == .code, position == line.caretStart, let block = line.codeBlock,
                  index == block.lowerBound + 1 else { return .passThrough }
            // 블록의 첫 줄 맨 앞. 빈 블록이면 블록을 없애고, 아니면 블록을 풀어 그 줄들을 본문으로 둔다
            // (``` 줄은 보이지 않으므로, 블록의 경계를 지우는 길이 여기다).
            let code = block.filter { doc.lines[$0].kind == .code }
            guard code.count == 1, line.end == line.caretStart else {
                guard let edit = toggleCodeBlock(doc, selection: selection) else { return .ignore }
                return .edit(edit)
            }
            let open = doc.lines[block.lowerBound]
            let last = doc.lines[block.upperBound]
            return .edit(TextEdit(
                range: NSRange(location: open.start, length: last.end - open.start),
                replacement: "",
                selection: NSRange(location: open.start, length: 0)
            ))
        }

        if line.continuationOf != nil, line.isVisualStart(position) {
            let start = doc.lines[index - 1].contentEnd
            return .edit(.insert("", replacing: NSRange(location: start, length: line.contentStart - start)))
        }
        if line.isVisualStart(position) {
            switch line.kind {
            case .todo, .bullet, .toggle, .toggleHeading, .quote, .heading:
                return .edit(TextEdit(
                    range: line.markerRange,
                    replacement: "",
                    selection: NSRange(location: position - line.markerLength, length: 0)
                ))
            case .paragraph where line.indentLength > 0:
                if line.isBlankParagraph, let edit = backspaceInOnlyEmptyToggleChild(doc, at: index) {
                    return .edit(edit)
                }
                return .edit(removingLastIndentUnit(doc, line: line, caret: position))
            default:
                break
            }
            guard index > 0 else { return position == line.start ? .passThrough : .ignore }
            let previous = doc.lines[index - 1]
            if previous.kind.isCode {
                // 코드 블록 바로 아랫줄: ``` 줄과 합치지 않는다. 빈 줄이면 지우고 블록의 마지막 줄로 간다.
                guard let block = previous.codeBlock else { return .ignore }
                // 줄이 없는 블록은 커서가 들어갈 줄이 없다. 블록을 지운다.
                guard let lastCode = block.last(where: { doc.lines[$0].kind == .code }) else {
                    let open = doc.lines[block.lowerBound]
                    return .edit(TextEdit(
                        range: NSRange(location: open.start, length: line.start - open.start),
                        replacement: "",
                        selection: NSRange(location: position - (line.start - open.start), length: 0)
                    ))
                }
                let target = doc.lines[lastCode].end
                guard line.range.length == 0 else { return .select(NSRange(location: target, length: 0)) }
                return .edit(TextEdit(
                    range: NSRange(location: previous.end, length: line.end - previous.end),
                    replacement: "",
                    selection: NSRange(location: target, length: 0)
                ))
            }
            if let join = joiningColoredBlocks(doc, before: index) { return .edit(join) }
            guard position > line.start else { return .passThrough }
            // 감춘 여는 기호 뒤에 커서가 있다. 기호가 아니라 줄바꿈을 지워 윗줄과 합친다.
            return .edit(TextEdit(
                range: NSRange(location: line.start - 1, length: 1),
                replacement: "",
                selection: NSRange(location: position - 1, length: 0)
            ))
        }

        let visible = line.visualStart(from: position)
        guard visible > line.contentStart else { return .ignore }
        let character = doc.characterRange(before: visible)
        if let edit = replacing(doc, character, with: "") {
            return .edit(edit)
        }
        guard visible != position else { return .passThrough }
        return .edit(TextEdit(range: character, replacement: "", selection: NSRange(location: character.location, length: 0)))
    }

    private static func backspaceInOnlyEmptyToggleChild(_ doc: MarkdownDocument, at row: Int) -> TextEdit? {
        guard let titleEnd = (0..<row).last(where: { !doc.lines[$0].isBlankParagraph }) else { return nil }
        let owner = doc.blockLines(at: titleEnd).lowerBound
        let toggle = doc.lines[owner]
        guard toggle.kind.isToggle, toggle.subtreeEnd == row + 1,
              doc.lines[(titleEnd + 1)..<row].allSatisfy({ $0.level <= toggle.level }) else { return nil }
        let child = doc.lines[row]
        let lastIndent = child.contentStart - 1
        // 단계에 포함되지 않은 끝 공백은 먼저 한 글자만 지운다.
        if doc.units[lastIndent] == 0x20,
           LineClassifier.indent(doc.units, from: child.start, to: lastIndent).level == child.level {
            return .insert("", replacing: NSRange(location: lastIndent, length: 1))
        }
        guard child.level == toggle.level + 1 else { return nil }
        let start = doc.lines[row - 1].end
        return TextEdit(range: NSRange(location: start, length: doc.lines[row].end - start), replacement: "",
                        selection: NSRange(location: doc.lines[titleEnd].contentEnd, length: 0))
    }

    /// ⌦ (선택이 없을 때).
    ///
    /// - 빈 본문 줄에서는 그 줄만 지우고 아랫줄의 글자 맨 앞으로 간다. 코드 블록 경계는 따로 처리한다.
    /// - 그 밖의 줄 끝에서는 줄바꿈과 함께 아랫줄의 감춘 줄 머리(들여쓰기, 목록과 제목의 기호)를
    ///   지운다. 그대로 두면 감춰 있던 기호가 글자로 드러난다. 코드 블록의 ``` 줄과는 합치지 않는다.
    /// - 그 밖에는 보이는 글자 하나를 지운다(⌫와 같은 규칙).
    static func deleteForward(_ doc: MarkdownDocument, selection: NSRange) -> KeyOutcome {
        guard selection.length == 0 else { return .passThrough }
        let position = selection.location
        let index = doc.lineIndex(at: position)
        let line = doc.lines[index]

        if line.hasHardBreak, position == line.contentEnd {
            return .edit(.insert("", replacing: NSRange(location: position, length: doc.lines[index + 1].contentStart - position)))
        }
        if line.kind.isCode {
            if let block = emptyBlock(doc, caretAt: position) { return .edit(removingBlock(doc, block)) }
            guard line.kind == .code, position == line.end else { return .passThrough }
            if index + 1 < doc.lines.count, doc.lines[index + 1].kind == .code { return .passThrough }
            // 블록의 마지막 줄 끝. 블록을 풀어 그 줄들을 본문으로 둔다(커서는 제자리).
            guard let block = line.codeBlock, var edit = toggleCodeBlock(doc, selection: selection) else { return .ignore }
            let open = doc.lines[block.lowerBound]
            edit.selection = NSRange(location: position - (NSMaxRange(open.fullRange) - open.start), length: 0)
            return .edit(edit)
        }

        if line.isVisualEnd(position) {
            guard index + 1 < doc.lines.count else { return position == line.end ? .passThrough : .ignore }
            let next = doc.lines[index + 1]
            if next.kind.isCode {
                // 줄이 없는 블록은 블록을 지운다.
                if let block = emptyBlock(doc, at: index + 1) {
                    let last = doc.lines[block.upperBound]
                    return .edit(TextEdit(range: NSRange(location: line.end, length: last.end - line.end), replacement: "", selection: selection))
                }
                // 코드 블록 바로 윗줄: ``` 줄과 합치지 않는다. 빈 줄이면 그 줄을 지운다.
                guard line.range.length == 0 else { return .ignore }
                return .edit(TextEdit(
                    range: NSRange(location: line.start, length: next.start - line.start),
                    replacement: "",
                    selection: NSRange(location: next.codeBlock.flatMap { block in
                        block.first { doc.lines[$0].kind == .code }.map { doc.lines[$0].caretStart - (next.start - line.start) }
                    } ?? line.start, length: 0)
                ))
            }
            if let join = joiningColoredBlocks(doc, before: index + 1) { return .edit(join) }
            if ListStructure.isBlank(line) {
                return .edit(TextEdit(
                    range: line.fullRange,
                    replacement: "",
                    selection: NSRange(location: next.caretStart - line.fullRange.length, length: 0)
                ))
            }
            if next.caretStart == next.start, position == line.end { return .passThrough }
            return .edit(TextEdit(
                range: NSRange(location: line.end, length: next.caretStart - line.end),
                replacement: "",
                selection: selection
            ))
        }

        let visible = line.visualEnd(from: position)
        let character = doc.characterRange(at: visible)
        if var edit = replacing(doc, character, with: "") {
            edit.selection = NSRange(location: min(position, edit.range.location), length: 0)
            return .edit(edit)
        }
        guard visible != position else { return .passThrough }
        return .edit(TextEdit(range: character, replacement: "", selection: selection))
    }
}
