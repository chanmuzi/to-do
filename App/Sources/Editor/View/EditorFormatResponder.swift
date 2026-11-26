import AppKit

/// 키 노트의 첫 응답자에게만 상단 메뉴의 서식 명령을 보낸다.
@MainActor package protocol EditorFormatResponder {
    func canPerformFormat(_ action: EditorAction) -> Bool
    func performFormat(_ action: EditorAction)
}

extension EditorTextView: EditorFormatResponder {
    package func canPerformFormat(_ action: EditorAction) -> Bool {
        guard isEditable, let editor, editor.isActive, editor.blockSelection != nil || !action.requiresBlockSelection,
              action.commitsComposition || !hasMarkedText() else { return false }
        return editor.canApplyFormat(action.editingAction)
    }

    package func performFormat(_ action: EditorAction) {
        editor?.perform(action)
    }
}

extension EditorController {
    /// 메뉴 검증은 현재 선택에서 만들 수 있는 편집만 계산한다. 원문과 다음 입력의 서식은 보존한다.
    fileprivate func canApplyFormat(_ action: EditorAction) -> Bool {
        let selection = clamped(selectedRange)
        if let blocks = blockSelection {
            let moving = action == .moveLineUp || action == .moveLineDown
            let rows = selectedBlockRows(blocks, includingChildren: moving)
            if moving {
                return EditorCommands.moveLines(document, selection: document.sourceRange(for: rows), folded: folded,
                    direction: action == .moveLineUp ? .up : .down, selectedRows: rows) != nil
            }
            let hidden = FoldState.hiddenLines(document, folded: folded)
            switch action {
            case .highlight:
                return (blocks.pastedRoots ?? Array(blocks.rows)).contains {
                    !hidden.contains($0) && document.lines[$0].continuationOf == nil && !document.lines[$0].kind.isCode && document.lines[$0].kind != .divider
                }
            case .toggleDone:
                return rows.contains { row in
                    guard !hidden.contains(row) else { return false }
                    let line = document.lines[row]
                    if case .todo = line.kind { return true }
                    return line.kind.isToggle
                }
            default: return false
            }
        }

        func canWrap(_ wrap: EditorCommands.Wrap) -> Bool {
            if selection.length > 0 { return EditorCommands.toggleWrap(document, selection: selection, wrap) != nil }
            return EditorCommands.toggleTyping(document, caret: selection.location, wrap, marks: currentTypingMarks() ?? TypingMarks()) != .unavailable
        }
        switch action {
        case .bold: return canWrap(.bold)
        case .strikethrough: return canWrap(.strike)
        case .underline: return canWrap(.underline)
        case .inlineCode: return canWrap(.code)
        case .link: return currentLinkTarget != nil
        case .highlight:
            if selection.length > 0 { return EditorCommands.setInk(document, selection: selection, color: Self.lastInk, toggle: true) != nil }
            return EditorCommands.typingInk(document, caret: selection.location, marks: currentTypingMarks() ?? TypingMarks(),
                                            color: Self.lastInk, toggle: true) != .unavailable
        case .heading(let level): return EditorCommands.toggleHeading(document, selection: selection, level: level) != nil
        case .toggleTodo: return EditorCommands.toggleTodo(document, selection: selection) != nil
        case .codeBlock: return EditorCommands.toggleCodeBlock(document, selection: selection) != nil
        case .toggleDone:
            let rows = document.lineRange(for: selection)
            let block = document.blockLines(at: rows.lowerBound)
            let line = document.lines[block.lowerBound]
            if block.contains(rows.upperBound), line.kind.isToggle { return true }
            return EditorCommands.toggleDone(document, selection: selection) != nil
        case .moveLineUp, .moveLineDown:
            return EditorCommands.moveLines(document, selection: selection, folded: folded, direction: action == .moveLineUp ? .up : .down) != nil
        default: return false
        }
    }
}
