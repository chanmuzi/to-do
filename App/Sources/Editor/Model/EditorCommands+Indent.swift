import Foundation

/// 편집 명령. 원문과 선택을 받아 바꿔 쓸 내용을 돌려주는 순수 함수다(화면을 모른다).
nonisolated enum EditorCommands {}

nonisolated extension EditorCommands {
    /// Tab. 줄을 한 단계 들여 쓴다. 코드 블록 안에서 선택이 없으면 그 자리에 탭을 넣는다.
    /// 접힌 토글은 감춘 줄과 함께 들여 쓴다(하위 줄이 토글에서 떨어져 나오지 않게).
    ///
    /// 들여 쓴 줄은 바로 앞 단계의 부모 항목(목록, 투두, 토글, 인용문) 아래에만 놓인다(D-043). 그래서 바로 앞의
    /// 비지 않은 줄보다 두 단계 깊어지지 않고, 위에 부모가 될 항목이 없는 본문 줄과 빈 줄은 들어가지 않는다.
    /// 여러 줄을 고르면 위에서부터 차례로 따진다(앞 줄이 들어가면 그 줄이 다음 줄의 부모가 될 수 있다).
    static func indent(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit? {
        let selected = doc.lineRange(for: selection)
        if selection.length == 0, doc.lines[selected.lowerBound].kind == .code {
            return .insert("\t", replacing: selection)
        }
        let lines = FoldState.expanded(selected, in: doc, folded: folded)
        let indented = indentableLines(doc, lines: lines, folded: folded)
        var edit = LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            switch line.kind {
            case .fenceOpen, .fenceClose: nil
            case .code: .init(oldLength: 0, new: "\t")
            default: indented.contains(line.start) ? .init(oldLength: 0, new: "\t") : nil
            }
        }
        edit?.includesHiddenLines = FoldState.hidesAny(of: lines, in: doc, folded: folded)
        return edit
    }

    /// 한 단계 들어갈 수 있는 줄의 시작 위치. 접혀서 감춘 줄은 제 토글을 따른다.
    private static func indentableLines(_ doc: MarkdownDocument, lines: ClosedRange<Int>, folded: Set<Int>) -> Set<Int> {
        var context = ListStructure.context(before: lines.lowerBound, in: doc)
        var result = Set<Int>()
        var movedRoots = Set<Int>()
        for index in lines {
            let line = doc.lines[index]
            var level = line.level
            let moves: Bool
            if let root = FoldState.foldRoot(of: index, in: doc, folded: folded), lines.contains(root) {
                moves = movedRoots.contains(root)
            } else {
                moves = !line.kind.isCode && line.level < MarkdownDocument.maxLevel && context.hasParent(atLevel: line.level)
                if moves { movedRoots.insert(index) }
            }
            if moves {
                result.insert(line.start)
                level += 1
            }
            context.add(line, level: level)
        }
        return result
    }

    /// ⇧Tab. 줄을 한 단계 내어 쓴다. 접힌 토글은 감춘 줄과 함께 내어 쓴다.
    static func outdent(_ doc: MarkdownDocument, selection: NSRange, folded: Set<Int> = []) -> TextEdit? {
        let selected = doc.lineRange(for: selection)
        let lines = FoldState.expanded(selected, in: doc, folded: folded)
        var edit = LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            let removable: Int
            switch line.kind {
            case .fenceOpen, .fenceClose: return nil
            case .code: removable = leadingIndentUnit(doc, at: line.start, limit: line.end, spaces: 4)
            default: removable = leadingIndentUnit(doc, at: line.start, limit: line.start + line.indentLength, spaces: 2)
            }
            return removable > 0 ? .init(oldLength: removable, new: "") : nil
        }
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
