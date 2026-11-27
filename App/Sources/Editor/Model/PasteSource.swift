import Foundation

/// 원문 조각의 물리 줄 번호를 기준으로, 상태를 옮겨야 할 토글만 담는다.
nonisolated struct PasteSource {
    var text: String
    var closedByRow: [Int: Bool] = [:]

    init(_ text: String) {
        self.text = text
    }

    enum TogglePolicy {
        case keep(FoldState)
        case closeAll
    }

    /// Float는 복사한 상태를, Notion은 모든 토글의 닫힘을 전달한다.
    init(_ text: String, toggles: TogglePolicy) {
        self.init(text)
        let fragment = MarkdownDocument(text)
        for row in fragment.lines.indices where fragment.lines[row].kind.isToggle {
            switch toggles {
            case .keep(let state): closedByRow[row] = state.isClosed(row, in: fragment)
            case .closeAll: closedByRow[row] = true
            }
        }
    }

    func applyFolds(to state: inout FoldState, in document: MarkdownDocument, firstRow: Int, insertionStart: Int) {
        for (offset, closed) in closedByRow {
            let row = firstRow + offset
            guard document.lines.indices.contains(row) else { continue }
            let line = document.lines[row]
            // 기존 토글 제목 한가운데에 붙은 첫 줄의 기호는 일반 글자다.
            guard line.kind.isToggle, line.start + line.indentLength >= insertionStart else { continue }
            if closed {
                state.closed.insert(row)
                state.openedEmpty.remove(row)
            } else {
                state.closed.remove(row)
                if FoldState.isEmptyToggle(row, in: document) { state.openedEmpty.insert(row) }
            }
        }
    }
}
