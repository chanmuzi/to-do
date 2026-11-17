import AppKit

// 원문은 그대로 두고 화면의 문단만 꾸민다. TextKit 2가 문단을 만들 때마다 여기서 속성을 얹는다.

extension EditorController: NSTextContentStorageDelegate {
    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
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
            style: style
        ))
        if let suggestion = dateSuggestion, index == dateSuggestionLine {
            for local in suggestion.expression.ranges {
                let marked = NSRange(location: line.contentStart + local.location - range.location, length: local.length)
                if NSMaxRange(marked) <= display.length {
                    display.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: style.text], range: marked)
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
        let offset = contentStorage.offset(from: contentStorage.documentRange.location, to: location)
        if dateSuggestionAbove, document.lineIndex(at: offset) == dateSuggestionLine {
            fragment.datePreviewMargin = dateHint.preferredSize.height + theme.space(.sp2)
        }
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
        guard editedMask.contains(.editedCharacters) else { return }
        let old = document
        document = MarkdownDocument(textStorage.string)
        documentVersion += 1
        if isSettingText {
            // 통째로 바꿔 넣은 글: 같은 줄 번호가 여전히 토글인 접힘만 남긴다.
            folded = FoldState.sanitized(folded, in: document)
            return
        }
        if isApplyingOutsideChange {
            // 바깥이 바꾼 글: 접힘은 줄 번호를 따라 옮기고, 바뀐 줄에 걸친 접힘은 편다. 사용자의 편집이
            // 아니므로 알리지 않는다.
            folded = FoldState.remapped(folded, old: old, new: document, editedRange: editedRange, delta: delta)
            folded.subtract(FoldState.brokenRoots(by: editedRange, in: document, folded: folded))
            return
        }
        // 미뤄 둔 바깥의 변경이 가리키는 자리를 이 편집만큼 옮긴다.
        // 조합 중인 글자보다 앞에 있는 변경은 조합이 바꾸는 글에 밀리지 않는다(같은 자리에 넣는 글자도 그 뒤다).
        if let deferred = deferredOutsideEdit,
           !(deferredEditPrecedesComposition && editedRange.location >= NSMaxRange(deferred.range) && NSMaxRange(editedRange) - delta >= NSMaxRange(deferred.range)) {
            deferredOutsideEdit?.shift(editedRange: editedRange, delta: delta)
        }
        if foldsBeforeEdit == nil { foldsBeforeEdit = folded }
        folded = FoldState.remapped(folded, old: old, new: document, editedRange: editedRange, delta: delta)
        if isReplayingUndo {
            // 되돌리기가 접혀서 감춘 줄을 고쳤으면 보이도록 편다(D-018). 접힘까지 적어 둔 편집이면
            // 다 돌아온 뒤에 그 접힘을 되살린다.
            folded.subtract(FoldState.brokenRoots(by: editedRange, in: document, folded: folded))
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
            folded: folded,
            hoveredLine: hoveredLink?.line,
            hoveredOffset: hoveredLink?.offset
        )
        if let cache = keysCache, cache.stamp == stamp { return cache.keys }
        let keys = LinePresentation.keys(for: document, folded: folded, hoveredLink: hoveredLink)
        keysCache = (stamp, keys)
        return keys
    }

    /// 모양이 달라진 줄만 다시 입힌다. 글자가 바뀐 줄은 TextKit이 스스로 다시 만든다.
    func refreshStyling() {
        guard !isRestyling else { return }
        updateTrailingLineStyle()
        let keys = currentKeys()
        defer { appliedKeys = keys }
        guard let changed = LinePresentation.changedLines(old: appliedKeys, new: keys) else { return }
        invalidate(lines: changed)
    }

    func restyleAll() {
        updateTrailingLineStyle()
        appliedKeys = currentKeys()
        invalidate(lines: 0..<document.lines.count)
    }

    /// 문서 끝의 빈 줄은 글자가 없어 문단이 만들어지지 않고, 앞 문단의 조각에 붙은 빈 줄 조각으로 놓인다.
    /// 그 줄의 들여쓰기와 높이는 텍스트 뷰의 기본 문단 모양을 따르므로, 그 줄이 닫히지 않은 코드 블록
    /// 안이면 코드 줄의 모양을 넣어 둔다. 원문 저장소에는 아무것도 더하지 않는다.
    private func updateTrailingLineStyle() {
        // 조합 중에는 텍스트 뷰의 속성을 건드리지 않는다. 조합이 끝나면 다시 불린다.
        guard !textView.hasMarkedText() else { return }
        let trailing = LinePresentation.trailingCodeLine(in: document).map {
            ParagraphStyler.trailingCodeLineStyle(level: $0.level, style: style)
        }
        guard trailing != appliedTrailingStyle else { return }
        appliedTrailingStyle = trailing
        textView.defaultParagraphStyle = trailing
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

    func measureContentHeight() -> CGFloat {
        let padding = theme.docPadding
        guard textContainer.size.width > 0 else { return padding.top + padding.bottom + style.body.lineHeight }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        // `usageBoundsForTextContainer`는 문단 높이가 줄어든 뒤에도 옛 값을 줄 때가 있어 마지막 조각의 아래 끝을 쓴다.
        var used: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.endLocation,
            options: [.reverse, .ensuresLayout]
        ) { fragment in
            used = fragment.layoutFragmentFrame.maxY
            return false
        }
        let text = ceil(max(used, style.body.lineHeight)) + padding.top + padding.bottom
        // 링크 주소 칸이 떠 있으면 그 아래 끝까지 보이게 한다.
        return linkSession == nil ? text : max(text, ceil(linkField.frame.maxY + EditorMetrics.linkFieldGap))
    }

    func reportContentHeight() {
        guard textContainer.size.width > 0 else { return }
        let height = measureContentHeight()
        guard abs(height - lastContentHeight) > 0.5 else { return }
        lastContentHeight = height
        onContentHeightChange?(height)
    }

    // MARK: 뷰에서 오는 알림

    func focusDidChange() {
        // 포커스가 바뀌면 정해 둔 서식은 버린다.
        typingMarks = nil
        dismissedDate = (text, selectedRange)
        updateDateSuggestion()
    }

    func windowDidChange() {
        refreshStyling()
        reportContentHeight()
    }

    func widthDidChange() {
        updateDateSuggestion()
        reportContentHeight()
        layoutCopyButton()
        layoutLinkField()
    }
}
