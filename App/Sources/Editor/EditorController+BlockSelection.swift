import AppKit

/// 앵커는 고정하고 포커스만 옮겨 반대 방향으로도 선택을 줄일 수 있다.
struct BlockSelection: Equatable {
    var anchor: Int
    var focus: Int

    var pastedRoots: [Int]?

    var rows: ClosedRange<Int> { min(anchor, focus)...max(anchor, focus) }

    func shifted(by count: Int) -> Self { Self(anchor: anchor + count, focus: focus + count, pastedRoots: pastedRoots?.map { $0 + count }) }
}

extension EditorController {
    private func block(at row: Int) -> ClosedRange<Int> {
        document.lines[row].codeBlock ?? document.blockLines(at: row)
    }

    func selectBlocks() {
        let rows = document.lineRange(for: clamped(selectedRange))
        showBlocks(BlockSelection(anchor: block(at: rows.lowerBound).lowerBound,
                                  focus: block(at: rows.upperBound).lowerBound))
    }

    func showBlocks(_ selection: BlockSelection) {
        setHoveredGutter(nil)
        blockSelection = selection
        let row = selection.focus
        let visible = document.lines[row].codeBlock?.first { document.lines[$0].kind == .code } ?? row
        setSelection(NSRange(location: document.lines[visible].caretStart, length: 0))
        textView.scrollRangeToVisible(selectedRange)
        textView.window?.invalidateCursorRects(for: textView)
        textView.needsDisplay = true
        textView.caret?.refresh()
        updateDateSuggestion()
    }

    @discardableResult
    func clearBlocks() -> Bool {
        guard blockSelection != nil else { return false }
        blockSelection = nil
        textView.window?.invalidateCursorRects(for: textView)
        textView.needsDisplay = true
        textView.caret?.refresh()
        return true
    }

    /// 문서가 구분선으로만 이루어져 있으면 삽입점을 둘 곳이 없어 블록 선택으로 남는다.
    func resolveDividerCaret() {
        let caret = clamped(selectedRange)
        let row = document.lineIndex(at: caret.location)
        guard blockSelection == nil, caret.length == 0, document.lines[row].kind == .divider,
              !textView.hasMarkedText() else { return }
        let next = CaretSnapping.snap(old: caret, new: caret, in: document, folded: folded)
        if document.line(at: next.location).kind == .divider {
            showBlocks(BlockSelection(anchor: row, focus: row))
        } else {
            setSelection(next)
        }
    }

    func dismissBlocks() -> Bool {
        guard clearBlocks() else { return false }
        resolveDividerCaret()
        return true
    }

    private func navigateBlocks(by direction: Int, extending: Bool) {
        guard let selection = blockSelection else { return }
        let hidden = FoldState.hiddenLines(document, folded: folded)
        var row = selection.focus + direction
        if extending, selection.focus >= selection.anchor {
            // 고정된 앵커 아래에서는 마지막 상자 안의 어느 줄에 포커스를 두어도 선택이 같다.
            let last = lastSelectedGroup(selection)
            row = direction > 0 ? last.upperBound + 1 : last.lowerBound - 1
        }
        while document.lines.indices.contains(row) {
            if !hidden.contains(row), block(at: row).lowerBound == row {
                showBlocks(BlockSelection(anchor: extending ? selection.anchor : row, focus: row))
                return
            }
            row += direction
        }
    }

    private func blockGroup(at row: Int) -> ClosedRange<Int> {
        row...max(block(at: row).upperBound, document.lines[row].subtreeEnd - 1)
    }

    private func lastSelectedGroup(_ selection: BlockSelection) -> ClosedRange<Int> {
        let rows = selection.rows
        var group = blockGroup(at: rows.lowerBound)
        while group.upperBound < rows.upperBound {
            group = blockGroup(at: group.upperBound + 1)
        }
        return group
    }

    func selectedBlockRows(_ selection: BlockSelection, includingChildren: Bool) -> ClosedRange<Int> {
        let end = includingChildren ? lastSelectedGroup(selection) : block(at: selection.rows.upperBound)
        return selection.rows.lowerBound...end.upperBound
    }

    func insertDivider() {
        let row = blockSelection?.rows.upperBound ?? document.lineIndex(at: selectedRange.location)
        let rows = block(at: row)
        let line = document.lines[rows.lowerBound]
        let last = document.lines[max(rows.upperBound, line.subtreeEnd - 1)]
        let indent = document.string(in: line.indentRange)
        let close = line.codeBlock != nil && document.lines[rows.upperBound].kind != .fenceClose ? "\n" + indent + "```" : ""
        clearBlocks()
        var edit = TextEdit.insert(close + "\n" + indent + "---\n" + indent, replacing: NSRange(location: last.end, length: 0))
        edit.includesHiddenLines = true
        apply(edit)
    }

    func selectAdjacentDivider(_ selection: NSRange, backward: Bool) -> Bool {
        guard selection.length == 0 else { return false }
        let row = document.lineIndex(at: selection.location)
        let line = document.lines[row]
        let adjacent = row + (backward ? -1 : 1)
        guard document.lines.indices.contains(adjacent), document.lines[adjacent].kind == .divider,
              FoldState.foldRoot(of: adjacent, in: document, folded: folded) == nil,
              backward ? line.isVisualStart(selection.location) : line.isVisualEnd(selection.location) else { return false }
        var target = adjacent
        if line.isBlankParagraph {
            let start = backward ? document.lines[adjacent].end : line.start
            let end = backward ? line.end : document.lines[adjacent].start
            apply(.insert("", replacing: NSRange(location: start, length: end - start)))
            if !backward { target -= 1 }
        }
        showBlocks(BlockSelection(anchor: target, focus: target))
        return true
    }

    func duplicateBlocks() {
        let old = blockSelection
        let caret = clamped(selectedRange)
        let current = block(at: document.lineIndex(at: caret.location)).lowerBound
        let rows = selectedBlockRows(old ?? BlockSelection(anchor: current, focus: current), includingChildren: true)
        let range = document.sourceRange(for: rows)
        let source = document.string(in: range)
        let end = NSMaxRange(range)
        var folds = Set(folded.map { $0 > rows.upperBound ? $0 + rows.count : $0 })
        folds.formUnion(folded.filter(rows.contains).map { $0 + rows.count })
        let offset = min(caret.location - range.location, range.length)
        let edit = TextEdit(range: NSRange(location: end, length: 0), replacement: "\n" + source,
                            selection: NSRange(location: end + 1 + offset, length: 0),
                            foldedAfter: folds, includesHiddenLines: true)
        let version = documentVersion
        apply(edit)
        if documentVersion != version, let old { showBlocks(old.shifted(by: rows.count)) }
    }

    func deleteBlocks() {
        guard let selection = blockSelection else { return }
        let rows = selectedBlockRows(selection, includingChildren: true)
        let start = rows.upperBound + 1 == document.lines.count && rows.lowerBound > 0
            ? document.lines[rows.lowerBound - 1].end : document.lines[rows.lowerBound].start
        let end = NSMaxRange(document.lines[rows.upperBound].fullRange)
        let version = documentVersion
        apply(TextEdit(range: NSRange(location: start, length: end - start), replacement: "",
                       selection: NSRange(location: start, length: 0), includesHiddenLines: true))
        if documentVersion != version {
            let row = max(0, rows.lowerBound - 1)
            let first = FoldState.foldRoot(of: row, in: document, folded: folded) ?? block(at: row).lowerBound
            showBlocks(BlockSelection(anchor: first, focus: first))
        }
    }

    func handleBlockCommand(_ selector: Selector) -> Bool {
        guard let selection = blockSelection else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)): navigateBlocks(by: -1, extending: false)
        case #selector(NSResponder.moveDown(_:)): navigateBlocks(by: 1, extending: false)
        case #selector(NSResponder.moveUpAndModifySelection(_:)): navigateBlocks(by: -1, extending: true)
        case #selector(NSResponder.moveDownAndModifySelection(_:)): navigateBlocks(by: 1, extending: true)
        case #selector(NSResponder.insertTab(_:)): run(.indent)
        case #selector(NSResponder.insertBacktab(_:)): run(.outdent)
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)): deleteBlocks()
        case #selector(NSResponder.cancelOperation(_:)): _ = dismissBlocks()
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertParagraphSeparator(_:)):
            let rows = block(at: selection.rows.lowerBound)
            if document.lines[rows.lowerBound].kind == .divider {
                let line = document.lines[rows.lowerBound]
                clearBlocks()
                apply(.insert("\n" + document.string(in: line.indentRange), replacing: NSRange(location: line.end, length: 0)))
                return true
            }
            let visible = rows.last { ![.fenceOpen, .fenceClose].contains(document.lines[$0].kind) } ?? rows.upperBound
            clearBlocks()
            setSelection(NSRange(location: document.lines[visible].contentEnd, length: 0))
        default: return false
        }
        return true
    }

    func editSelectedBlocks(_ action: EditorAction) -> Bool {
        guard let selection = blockSelection else { return false }
        let includeChildren = action == .moveLineUp || action == .moveLineDown || action == .indent || action == .outdent
        let rows = selectedBlockRows(selection, includingChildren: includeChildren)
        let range = document.sourceRange(for: rows)
        var edit: TextEdit?
        switch action {
        case .fold, .unfold:
            let caret = NSRange(location: document.lines[selection.focus].contentStart, length: 0)
            performFoldCommand(action, at: caret, moveCaret: false)
            if action == .fold, let root = FoldState.foldRoot(of: selection.focus, in: document, folded: folded) {
                showBlocks(BlockSelection(anchor: root, focus: root))
            }
            return true
        case .pasteInside: paste(from: .general, inside: true); return true
        case .duplicate: duplicateBlocks(); return true
        case .indent: edit = EditorCommands.indent(document, selection: range, folded: folded)
        case .outdent: edit = EditorCommands.outdent(document, selection: range, folded: folded)
        case .toggleDone:
            let hidden = FoldState.hiddenLines(document, folded: folded)
            let toggles = rows.filter { row in
                !hidden.contains(row) && document.lines[row].kind.isToggle
            }
            let next = foldState.toggling(Set(toggles), in: document)
            edit = EditorCommands.toggleDone(document, lines: rows, selection: range, excluding: hidden, invertEach: true)
            if edit == nil {
                changeUserFolds(next)
                showVisibleBlocks(selection)
                return true
            }
            edit?.foldedAfter = next.closed
            edit?.openedEmptyAfter = next.openedEmpty
            edit?.includesHiddenLines = true
        case .moveLineUp, .moveLineDown:
            edit = EditorCommands.moveLines(document, selection: range, folded: folded, openedEmpty: foldState.openedEmpty,
                                            direction: action == .moveLineUp ? .up : .down, selectedRows: rows)
        default: return true
        }
        guard var edit else { return true }
        let shifted = MarkdownDocument(edit.applied(to: document.text)).lineIndex(at: edit.selection.location) - rows.lowerBound
        edit.selection.length = 0
        let version = documentVersion
        let previous = folded
        apply(edit)
        if documentVersion != version {
            if action == .toggleDone, previous != folded {
                startFoldMotion(from: previous, to: folded)
                if !foldTransitions.isEmpty { refreshStyling() }
            }
            showVisibleBlocks(selection.shifted(by: shifted))
        }
        return true
    }

    private func showVisibleBlocks(_ selection: BlockSelection) {
        func visible(_ row: Int) -> Int { FoldState.foldRoot(of: row, in: document, folded: folded) ?? row }
        showBlocks(BlockSelection(anchor: visible(selection.anchor), focus: visible(selection.focus)))
    }

    /// 줄바꿈과 문단 간격까지 배치한 칸을 쓴다. 문서 끝의 빈 줄은 앞 문단과 다른 칸이다.
    private func blockLineFrame(at row: Int) -> CGRect? {
        let line = document.lines[row]
        if line.fullRange.length == 0 { return caretSpot(line.start, lineIndex: row)?.line }
        guard let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: line.start),
              let fragment = layoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment else { return nil }
        ensureLayout(for: fragment.rangeInElement)
        var frame = fragment.layoutFragmentFrame
        frame.size.height = min(fragment.ownHeight, fragment.emptyToggleHintRect?.minY ?? fragment.ownHeight)
        return frame
    }

    func blockSelectionRects() -> [CGRect] {
        guard let selection = blockSelection else { return [] }
        let hidden = FoldState.hiddenLines(document, folded: folded)
        var rects: [CGRect] = []
        var row = selection.rows.lowerBound
        while row <= selection.rows.upperBound {
            let end = blockGroup(at: row).upperBound + 1
            if let rect = blockRect(row..<end, hidden: hidden) { rects.append(rect) }
            row = end
        }
        return rects
    }

    private func blockRect(_ rows: Range<Int>, hidden: Set<Int>) -> CGRect? {
        let first = rows.lowerBound
        guard !hidden.contains(first), let last = rows.last(where: { !hidden.contains($0) }),
              let top = blockLineFrame(at: first)?.minY, let bottom = blockLineFrame(at: last)?.maxY else { return nil }
        let hasMarker = scheduleButtons.keys.contains { rows.contains($0) && !hidden.contains($0) && hasScheduleMarker(at: $0) }
        let right = textContainer.size.width - (hasMarker ? theme.component(.noteTopButtonSize) : 0)
        let origin = textView.textContainerOrigin
        let gap = theme.component(.editorBlockGap)
        let left = CGFloat(document.lines[first].level) * style.indent - theme.component(.editorBlockPadX)
        return CGRect(x: origin.x + left, y: origin.y + top + gap / 2,
                      width: max(0, right - left), height: max(0, bottom - top - gap))
    }

    func drawBlockColors(in dirty: NSRect) {
        let hidden = FoldState.hiddenLines(document, folded: folded)
        let radius = theme.shape(.chipRadius)
        let viewport = layoutManager.textViewportLayoutController.viewportRange ?? contentStorage.documentRange
        let base = contentStorage.documentRange.location
        let first = document.lineIndex(at: contentStorage.offset(from: base, to: viewport.location))
        let last = document.lineIndex(at: contentStorage.offset(from: base, to: viewport.endLocation))
        for row in first...document.blockLines(at: last).upperBound {
            let line = document.lines[row]
            guard let ink = line.blockInk, !ink.foreground else { continue }
            let rows = document.blockLines(at: row)
            guard let rect = blockRect(rows.lowerBound..<(rows.upperBound + 1), hidden: hidden), dirty.intersects(rect) else { continue }
            style.ink(ink, done: document.lines[rows.lowerBound].kind == .todo(done: true)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }

    func drawBlockSelection(in dirty: NSRect) {
        guard blockSelection != nil else { return }
        theme.nsColor(.editorSelection).setFill()
        let radius = theme.shape(.chipRadius)
        for rect in blockSelectionRects() where rect.intersects(dirty) {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}
