import Foundation

/// 편집 명령. 원문과 선택을 받아 바꿔 쓸 내용을 돌려주는 순수 함수다(화면을 모른다).
nonisolated enum EditorCommands {}

nonisolated extension EditorCommands {
    /// Tab. 줄을 한 단계 들여 쓴다. 코드 블록 안에서 선택이 없으면 그 자리에 탭을 넣는다.
    static func indent(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        let lines = doc.lineRange(for: selection)
        if selection.length == 0, doc.lines[lines.lowerBound].kind == .code {
            return .insert("\t", replacing: selection)
        }
        return LinePrefixEdit.make(doc, lines: lines, selection: selection) { line in
            switch line.kind {
            case .fenceOpen, .fenceClose: nil
            case .code: .init(oldLength: 0, new: "\t")
            default: line.level < MarkdownDocument.maxLevel ? .init(oldLength: 0, new: "\t") : nil
            }
        }
    }

    /// ⇧Tab. 줄을 한 단계 내어 쓴다.
    static func outdent(_ doc: MarkdownDocument, selection: NSRange) -> TextEdit? {
        LinePrefixEdit.make(doc, lines: doc.lineRange(for: selection), selection: selection) { line in
            let removable: Int
            switch line.kind {
            case .fenceOpen, .fenceClose: return nil
            case .code: removable = leadingIndentUnit(doc, at: line.start, limit: line.end, spaces: 4)
            default: removable = leadingIndentUnit(doc, at: line.start, limit: line.start + line.indentLength, spaces: 2)
            }
            return removable > 0 ? .init(oldLength: removable, new: "") : nil
        }
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
