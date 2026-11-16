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
        return NSTextParagraph(attributedString: ParagraphStyler.display(
            source: storage.attributedSubstring(from: range),
            line: line,
            key: keys[index],
            style: style
        ))
    }
}

extension EditorController: NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}

extension EditorController: NSTextStorageDelegate {
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
        let remapped = isSettingText
            ? FoldState.sanitized(folded, in: document)
            : FoldState.remapped(folded, old: old, new: document, editedRange: editedRange, delta: delta)
        if remapped != folded {
            folded = remapped
            foldChangedByEdit = true
        }
    }
}

extension EditorController {
    /// 편집 중인 것으로 보는지. 본문에 포커스가 있고 창이 키 창일 때다.
    var isActive: Bool {
        guard let window = textView.window, window.firstResponder === textView else { return false }
        return window.isKeyWindow || forcesActiveAppearance
    }

    /// 지금 상태(원문, 선택, 접힘, 마우스)에서의 줄별 모양.
    func currentKeys() -> [LineRenderKey] {
        var active: ClosedRange<Int>?
        if isActive {
            let selection = clamped(textView.selectedRange())
            active = document.lineIndex(at: selection.location)...document.lineIndex(at: NSMaxRange(selection))
        }
        // 문단을 만들 때마다 불리므로 같은 상태에서는 다시 계산하지 않는다.
        let stamp = KeyStamp(
            documentVersion: documentVersion,
            active: active,
            folded: folded,
            hoveredLine: hoveredLink?.line,
            hoveredOffset: hoveredLink?.offset
        )
        if let cache = keysCache, cache.stamp == stamp { return cache.keys }
        let keys = LinePresentation.keys(for: document, active: active, folded: folded, hoveredLink: hoveredLink)
        keysCache = (stamp, keys)
        return keys
    }

    /// 모양이 달라진 줄만 다시 입힌다. 글자가 바뀐 줄은 TextKit이 스스로 다시 만든다.
    func refreshStyling() {
        guard !isRestyling else { return }
        let keys = currentKeys()
        defer { appliedKeys = keys }
        guard let changed = LinePresentation.changedLines(old: appliedKeys, new: keys) else { return }
        invalidate(lines: changed)
    }

    func restyleAll() {
        appliedKeys = currentKeys()
        invalidate(lines: 0..<document.lines.count)
    }

    /// 그 줄들의 문단을 다시 만들게 한다. 원문의 글자는 건드리지 않는다(속성이 바뀌었다고만 알린다).
    private func invalidate(lines: Range<Int>) {
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
        return ceil(max(used, style.body.lineHeight)) + padding.top + padding.bottom
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
        refreshStyling()
    }

    func windowDidChange() {
        refreshStyling()
        reportContentHeight()
    }

    func widthDidChange() {
        reportContentHeight()
        layoutCopyButton()
    }
}
