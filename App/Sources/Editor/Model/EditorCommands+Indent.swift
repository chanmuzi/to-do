import Foundation

/// 편집 명령. 원문과 선택을 받아 바꿔 쓸 내용을 돌려주는 순수 함수다(화면을 모른다).
nonisolated enum EditorCommands {}

nonisolated extension EditorCommands {
    /// Tab. 줄을 한 단계 들여 쓴다. 코드 블록 안에서 선택이 없으면 그 자리에 탭을 넣는다.
    /// 접힌 토글은 감춘 줄과 함께 들여 쓴다(하위 줄이 토글에서 떨어져 나오지 않게).
    ///
    /// 들여 쓴 줄은 바로 앞 단계의 부모 항목(목록, 투두, 토글, 인용문) 아래에만 놓인다(D-043). 그래서 바로 앞의
    /// 비지 않은 줄보다 두 단계 깊어지지 않고, 위에 부모가 될 항목이 없는 본문 줄과 빈 줄은 들어가지 않는다.
    static func indent(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit? {
        if selection.length == 0, doc.line(at: selection.location).kind == .code {
            return .insert("\t", replacing: selection)
        }
        return shiftIndent(doc, selection: selection, folded: folded, inward: true)
    }

    static func outdent(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit? {
        shiftIndent(doc, selection: selection, folded: folded, inward: false)
    }

    private static func shiftIndent(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int>, inward: Bool) -> TextEdit? {
        let selected = doc.lineRange(for: selection)
        let lines = FoldState.expanded(selected, in: doc, folded: folded)
        let group = lines.count > 1
        let codeOnly = lines.allSatisfy { doc.lines[$0].kind == .code }
        let targets = doc.lines[lines].filter { line in
            !group || !(line.isBlankParagraph || (line.kind == .code && line.contentRange.length == 0))
        }
        guard let level = targets.map(\.level).min() else { return nil }
        if !codeOnly {
            // 울타리 한쪽만 들여 쓰면 블록의 단계와 코드 내용이 달라진다.
            guard targets.allSatisfy({ line in
                guard let block = line.codeBlock else { return true }
                return group && lines.contains(block.lowerBound) && lines.contains(block.upperBound)
            }) else { return nil }
            if inward {
                let context = ListStructure.context(before: lines.lowerBound, in: doc)
                guard context.hasParent(atLevel: level),
                      targets.allSatisfy({ $0.level < MarkdownDocument.maxLevel }) else { return nil }
            } else if group && level == 0 { return nil }
        }
        var changes: [Int: LinePrefixEdit.Change] = [:]
        for line in targets {
            if inward {
                changes[line.start] = .init(oldLength: 0, new: "\t")
            } else if group, !codeOnly, line.indentLength >= 2,
                      doc.units[line.start] == 0x20, doc.units[line.start + 1] == 0x09 {
                // 공백 하나 뒤의 탭이 한 단계다. 공백만 지우면 깊이가 그대로 남는다.
                changes[line.start] = .init(oldLength: 2, new: " ")
            } else {
                let limit = codeOnly ? line.end : line.start + line.indentLength
                let length = leadingIndentUnit(doc, at: line.start, limit: limit, spaces: codeOnly ? 4 : 2)
                guard length > 0 else { return nil }
                changes[line.start] = .init(oldLength: length, new: "")
            }
        }
        var edit = LinePrefixEdit.make(doc, lines: lines, selection: selection) { changes[$0.start] }
        edit?.includesHiddenLines = FoldState.hidesAny(of: lines, in: doc, folded: folded)
        return edit
    }

    /// 줄 맨 앞의 들여쓰기 한 단위(탭 하나 또는 공백 `spaces`개까지)의 길이.
    static func leadingIndentUnit(_ doc: MarkdownDocument, at start: Int, limit: Int, spaces: Int) -> Int {
        guard start < limit else { return 0 }
        if doc.units[start] == 0x09 { return 1 }
        var count = 0
        while count < spaces, start + count < limit, doc.units[start + count] == 0x20 { count += 1 }
        return count
    }
}
