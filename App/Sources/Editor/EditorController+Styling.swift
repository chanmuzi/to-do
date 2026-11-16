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
        if isAppendingFromOutside {
            // 바깥이 끝에 덧붙인 글: 접힘은 줄 번호를 따라 옮기기만 한다. 사용자의 편집이 아니므로
            // 알리지 않고 되돌리기에도 적지 않는다.
            folded = FoldState.remapped(folded, old: old, new: document, editedRange: editedRange, delta: delta)
            return
        }
        if foldsBeforeEdit == nil { foldsBeforeEdit = folded }
        folded = FoldState.remapped(folded, old: old, new: document, editedRange: editedRange, delta: delta)
        if isReplayingUndo {
            // 되돌리기가 접혀서 감춘 줄을 고쳤으면 보이도록 편다(D-018). 접힘까지 적어 둔 편집이면
            // 다 돌아온 뒤에 그 접힘을 되살린다.
            folded.subtract(FoldState.brokenRoots(by: editedRange, in: document, folded: folded))
        } else {
            editsSinceFlush.append((old, editedRange, delta))
        }
        markTextChanged()
    }
}

extension EditorController {
    /// 편집 중인 것으로 보는지. 본문에 포커스가 있고 창이 키 창일 때다. 커서 줄의 기호를 보일지와
    /// 편집 단축키를 받을지를 이것으로 정한다.
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
        updateTrailingLineStyle()
        let keys = currentKeys()
        defer { appliedKeys = keys }
        guard let changed = LinePresentation.changedLines(old: appliedKeys, new: keys) else { return }
        invalidate(lines: changed)
        scheduleHeightReport()
    }

    /// 줄의 모양만 바뀌어도 높이가 달라질 수 있다: 커서가 들어간 줄은 감췄던 기호(링크의 주소 등)가 보여
    /// 줄이 넘어가고, 커서가 나가거나 창이 키 창에서 물러나면 다시 줄어든다. 글이 바뀐 것이 아니어서
    /// 따로 알려야 창 높이가 따라온다. 선택이 바뀌는 도중일 수 있으므로 다음 메인 큐 차례에 잰다.
    func scheduleHeightReport() {
        guard !isHeightReportScheduled else { return }
        isHeightReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isHeightReportScheduled = false
            self.reportContentHeight()
        }
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
