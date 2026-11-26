import AppKit

// 원문은 그대로 두고 화면의 문단만 꾸민다. TextKit 2가 문단을 만들 때마다 여기서 속성을 얹는다.

extension EditorController: NSTextContentStorageDelegate {
    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        let interval = EditorTrace.begin("textParagraphWith")
        defer { EditorTrace.end("textParagraphWith", interval) }
        guard let storage = textContentStorage.textStorage, NSMaxRange(range) <= storage.length else { return nil }
        let index = document.lineIndex(at: range.location)
        let line = document.lines[index]
        // 원문과 풀어 둔 줄이 어긋나 있으면(있어서는 안 된다) 꾸미지 않은 문단을 쓴다.
        guard line.fullRange == range else { return nil }
        let keys = currentKeys()
        let display = NSMutableAttributedString(attributedString: ParagraphStyler.display(
            source: storage.attributedSubstring(from: range),
            line: line,
            key: keys[index],
            style: style,
            scheduleInset: hasScheduleMarker(at: index) ? theme.component(.noteTopButtonSize) : 0
        ))
        if let suggestion = dateSuggestion, let owner = dateSuggestionLine, owner == (line.continuationOf ?? index) {
            for local in suggestion.expression.ranges {
                let match = NSRange(location: document.lines[owner].contentStart + local.location, length: local.length)
                let part = NSIntersectionRange(match, line.contentRange)
                if part.length > 0 {
                    let marked = NSRange(location: part.location - range.location, length: part.length)
                    display.addAttributes([.underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue, .underlineColor: style.text2], range: marked)
                }
            }
        }
        return NSTextParagraph(attributedString: display)
    }
}

extension EditorController: NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.foldDrawing = foldDrawing
        let offset = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
        fragment.row = document.lineIndex(at: offset)
        return fragment
    }
}

extension EditorController: NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // 원문 저장소에는 기본 글꼴과 글자색만 둔다. 텍스트 뷰의 기본 문단 모양(`updateTrailingLineStyle`)을
        // 바꾸면 서식 없는 텍스트 뷰가 그것을 저장소의 글자에도 붙이므로, 들어오는 길목에서 떼어 낸다.
        guard editedRange.length > 0, NSMaxRange(editedRange) <= textStorage.length else { return }
        textStorage.removeAttribute(.paragraphStyle, range: editedRange)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // 글자가 바뀌면 문단을 다시 만들기 전에 곧바로 다시 푼다(문단을 만들 때 이 값을 쓴다).
        if let pending = pendingHeightRange {
            // 연속 편집이면 앞서 기록한 원문 좌표도 움직일 수 있다.
            pendingHeightRange = editedMask.contains(.editedCharacters)
                ? NSRange(location: 0, length: textStorage.length) : NSUnionRange(pending, editedRange)
        } else {
            pendingHeightRange = editedRange
        }
        guard editedMask.contains(.editedCharacters) else { return }
        setHoveredGutter(nil)
        let old = document
        stopFoldMotion()
        // 저장소 편집 중에는 삽입점이나 커서 영역을 다시 배치하지 않는다.
        blockSelection = nil
        document = EditorTrace.measure("didProcessEditing.parse") {
            if isSettingText { return MarkdownDocument(textStorage.string) }
            return MarkdownDocument(updating: old, text: textStorage.string, editedRange: editedRange, delta: delta)
        }
        lastBodyEdit = (old.text, NSRange(location: editedRange.location, length: editedRange.length - delta))
        documentVersion += 1
        if isSettingText {
            // 통째로 바꿔 넣은 글: 같은 줄 번호가 여전히 토글인 접힘만 남긴다.
            foldState = foldState.sanitized(in: document)
            return
        }
        if isApplyingOutsideChange {
            // 바깥이 바꾼 글: 접힘은 줄 번호를 따라 옮기고, 바뀐 줄에 걸친 접힘은 편다. 사용자의 편집이
            // 아니므로 알리지 않는다.
            foldState = foldState.remapped(old: old, new: document, editedRange: editedRange, delta: delta)
            foldState.closed.subtract(FoldState.brokenRoots(by: editedRange, in: document, folded: folded))
            return
        }
        // 미뤄 둔 바깥의 변경이 가리키는 자리를 이 편집만큼 옮긴다.
        // 조합 중인 글자보다 앞에 있는 변경은 조합이 바꾸는 글에 밀리지 않는다(같은 자리에 넣는 글자도 그 뒤다).
        if let deferred = deferredOutsideEdit,
           !(deferredEditPrecedesComposition && editedRange.location >= NSMaxRange(deferred.range) && NSMaxRange(editedRange) - delta >= NSMaxRange(deferred.range)) {
            deferredOutsideEdit?.shift(editedRange: editedRange, delta: delta)
        }
        if foldsBeforeEdit == nil { foldsBeforeEdit = foldState }
        foldState = foldState.remapped(old: old, new: document, editedRange: editedRange, delta: delta)
        if isReplayingUndo {
            // 되돌리기가 접혀서 감춘 줄을 고쳤으면 보이도록 편다(D-018). 접힘까지 적어 둔 편집이면
            // 다 돌아온 뒤에 그 접힘을 되살린다.
            foldState.closed.subtract(FoldState.brokenRoots(by: editedRange, in: document, folded: folded))
        } else {
            editsSinceFlush.append((old, editedRange, delta))
            recordForUndo(old: old, editedRange: editedRange, delta: delta)
        }
        markTextChanged()
    }
}

extension EditorController {
    /// 편집 중인 것으로 보는지. 본문에 포커스가 있고 창이 키 창일 때다. 편집 단축키를 받을지를 이것으로 정한다.
    var isActive: Bool {
        guard let window = textView.window, window.firstResponder === textView else { return false }
        return window.isKeyWindow || forcesActiveAppearance
    }

    /// 지금 상태(원문, 접힘, 마우스)에서의 줄별 모양. 커서가 어디에 있든 같다(기호는 늘 감춘다).
    func currentKeys() -> [LineRenderKey] {
        // 문단을 만들 때마다 불리므로 같은 상태에서는 다시 계산하지 않는다.
        let stamp = KeyStamp(
            documentVersion: documentVersion,
            foldState: foldState,
            animating: Set(foldTransitions.keys),
            hoveredLine: hoveredLink?.line,
            hoveredOffset: hoveredLink?.offset
        )
        if let cache = keysCache, cache.stamp == stamp { return cache.keys }
        let keys = EditorTrace.measure("LinePresentation.keys") {
            LinePresentation.keys(for: document, folded: folded, openedEmpty: foldState.openedEmpty,
                                  hoveredLink: hoveredLink, animating: stamp.animating)
        }
        keysCache = (stamp, keys)
        return keys
    }

    /// 모양이 달라진 줄만 다시 입힌다. 글자가 바뀐 줄은 TextKit이 스스로 다시 만든다.
    func refreshStyling() {
        guard !isRestyling else { return }
        updateTrailingLineStyle()
        let keys = currentKeys()
        guard appliedStamp != keysCache?.stamp else { return }
        let previous = appliedKeys
        appliedKeys = keys
        appliedStamp = keysCache?.stamp
        guard let changed = LinePresentation.changedLines(old: previous, new: keys) else { return }
        invalidate(lines: changed)
    }

    func restyleAll() {
        updateTrailingLineStyle()
        appliedKeys = currentKeys()
        appliedStamp = keysCache?.stamp
        invalidate(lines: 0..<document.lines.count)
    }

    /// 문서 끝의 빈 줄은 글자가 없어 문단이 만들어지지 않고, 앞 문단의 조각에 붙은 빈 줄 조각으로 놓인다.
    /// 그 줄의 들여쓰기와 높이는 텍스트 뷰의 기본 문단 모양을 따르므로, 그 줄이 닫히지 않은 코드 블록
    /// 안이면 코드 줄의 모양을 넣어 둔다. 원문 저장소에는 아무것도 더하지 않는다.
    private func updateTrailingLineStyle() {
        // 조합 중에는 텍스트 뷰의 속성을 건드리지 않는다. 조합이 끝나면 다시 불린다.
        guard !textView.hasMarkedText() else { return }
        var trailing = LinePresentation.trailingCodeLine(in: document).map {
            ParagraphStyler.trailingCodeLineStyle(level: $0.level, style: style)
        }
        if let last = document.lines.last, last.range.length == 0, last.continuationOf != nil,
           let key = currentKeys().last {
            let sample = ParagraphStyler.display(source: NSAttributedString(string: " "), line: last, key: key, style: style)
            trailing = sample.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        }
        guard trailing != appliedTrailingStyle else { return }
        appliedTrailingStyle = trailing
        setInputParagraph(trailing ?? style.bodyParagraph)
        // 빈 줄 조각이 붙어 있는 마지막 문단을 다시 놓게 한다.
        if document.lines.count >= 2 { invalidate(lines: (document.lines.count - 2)..<(document.lines.count - 1)) }
    }

    /// 그 줄들의 문단을 다시 만들게 한다. 원문의 글자는 건드리지 않는다(속성이 바뀌었다고만 알린다).
    func invalidate(lines: Range<Int>) {
        guard let storage = textView.textStorage, !lines.isEmpty else { return }
        let start = document.lines[lines.lowerBound].start
        let end = NSMaxRange(document.lines[lines.upperBound - 1].fullRange)
        let range = NSRange(location: start, length: min(end, storage.length) - start)
        guard range.length > 0 else { return }
        isRestyling = true
        contentStorage.performEditingTransaction {
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
        }
        isRestyling = false
        textView.needsDisplay = true
        textView.caret?.reposition()
    }

    // MARK: 높이

    func ensureLayout(for range: NSTextRange) {
        EditorTrace.measure("ensureLayout") { layoutManager.ensureLayout(for: range) }
    }

    func measureContentHeight() -> CGFloat {
        let interval = EditorTrace.begin("measureContentHeight")
        defer { EditorTrace.end("measureContentHeight", interval) }
        let padding = theme.docPadding
        guard textContainer.size.width > 0 else { return padding.top + padding.bottom + style.body.lineHeight }
        let dirty = pendingHeightRange
        pendingHeightRange = nil
        let count = document.lines.count
        if heightLayoutWidth != textContainer.size.width || measuredParagraphHeights.count != count || dirty?.length == document.length {
            measureAllParagraphs()
        } else if let dirty {
            let first = max(0, document.lineIndex(at: dirty.location) - 1)
            let last = min(count - 1, document.lineIndex(at: NSMaxRange(dirty)) + 1)
            updateParagraphHeights(first...last)
        }
        heightLayoutWidth = textContainer.size.width
        let text = ceil(max(measuredTextHeight, style.body.lineHeight)) + padding.top + padding.bottom
        // 링크 주소 칸이 떠 있으면 그 아래 끝까지 보이게 한다.
        return linkSession == nil ? text : max(text, ceil(linkField.frame.maxY + style.metrics.linkFieldGap))
    }

    /// 전체를 처음 배치할 때 얻은 마지막 y 좌표와 각 문단의 높이를 보관한다.
    private func measureAllParagraphs() {
        let bounds = layoutManager.documentRange
        ensureLayout(for: bounds)
        measuredParagraphHeights = Array(repeating: 0, count: document.lines.count)
        measuredTextHeight = 0
        layoutManager.enumerateTextLayoutFragments(from: bounds.location, options: [.ensuresLayout]) { fragment in
            let offset = self.contentStorage.offset(from: bounds.location, to: fragment.rangeInElement.location)
            let row = self.document.lineIndex(at: offset)
            self.measuredParagraphHeights[row] = fragment.layoutFragmentFrame.height
            self.measuredTextHeight = fragment.layoutFragmentFrame.maxY
            return true
        }
    }

    /// 앞쪽 문단만 다시 배치하면 TextKit은 먼 끝 조각의 y를 추정한다. 확정한 전체 높이에
    /// 바뀐 조각의 실제 높이 차이만 더한다. 문서 끝의 빈 줄은 앞 문단 조각에 포함된다.
    private func updateParagraphHeights(_ rows: ClosedRange<Int>) {
        let bounds = layoutManager.documentRange
        guard let start = contentStorage.location(bounds.location, offsetBy: document.lines[rows.lowerBound].start),
              let end = contentStorage.location(bounds.location, offsetBy: NSMaxRange(document.lines[rows.upperBound].fullRange)),
              let range = NSTextRange(location: start, end: end) else { measureAllParagraphs(); return }
        ensureLayout(for: range)
        var heights = Array(repeating: CGFloat.zero, count: rows.count)
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let offset = self.contentStorage.offset(from: bounds.location, to: fragment.rangeInElement.location)
            let row = self.document.lineIndex(at: offset)
            guard row <= rows.upperBound else { return false }
            if rows.contains(row) { heights[row - rows.lowerBound] = fragment.layoutFragmentFrame.height }
            return row < rows.upperBound
        }
        for (row, height) in zip(rows, heights) {
            measuredTextHeight += height - measuredParagraphHeights[row]
            measuredParagraphHeights[row] = height
        }
    }

    func reportContentHeight() {
        guard textContainer.size.width > 0 else { return }
        let height = measureContentHeight()
        layoutScheduleButtons()
        guard abs(height - lastContentHeight) > 0.5 else { return }
        lastContentHeight = height
        onContentHeightChange?(height)
    }

    // MARK: 뷰에서 오는 알림

    func focusDidChange() {
        // 포커스가 바뀌면 정해 둔 서식은 버린다.
        typingMarks = nil
        updateDateSuggestion()
    }

    func windowDidChange() {
        refreshStyling()
        reportContentHeight()
    }

    func widthDidChange() {
        setHoveredGutter(nil)
        updateDateSuggestion()
        layoutCopyButton()
        layoutLinkField()
        reportContentHeight()
        if linkSession != nil { textView.scrollToVisible(linkField.frame) }
    }
}
