import AppKit

extension EditorController {
    /// 마우스 아래에 있는 누를 수 있는 것.
    enum Hit: Equatable {
        case checkbox(line: Int)
        case chevron(line: Int)
        /// 열 수 있는 주소(`LinkPolicy`)의 링크.
        case link(line: Int, offset: Int, url: URL)
    }

    /// 그 점(텍스트 뷰 좌표)의 문단 조각과 줄 번호.
    private func fragment(at point: CGPoint) -> (fragment: MarkdownLayoutFragment, line: Int, local: CGPoint)? {
        let origin = textView.textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) as? MarkdownLayoutFragment else { return nil }
        let frame = fragment.layoutFragmentFrame
        guard containerPoint.y >= frame.minY, containerPoint.y < frame.maxY else { return nil }
        let offset = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
        guard offset >= 0, offset <= document.length else { return nil }
        let local = CGPoint(x: containerPoint.x - frame.minX, y: containerPoint.y - frame.minY)
        return (fragment, document.lineIndex(at: offset), local)
    }

    func hit(at point: CGPoint) -> Hit? {
        guard let found = fragment(at: point) else { return nil }
        guard FoldState.foldRoot(of: found.line, in: document, folded: folded) == nil else { return nil }
        let line = document.lines[found.line]
        if let gutter = found.fragment.gutterRect, gutter.contains(found.local) {
            switch line.kind {
            case .todo: return .checkbox(line: found.line)
            case .toggle, .toggleHeading: return .chevron(line: found.line)
            default: return nil
            }
        }
        // 웹 주소와 메일 주소만 누를 수 있다. 다른 주소의 링크는 보통 글자처럼 다룬다.
        if let link = found.fragment.link(at: found.local), let url = LinkPolicy.openableURL(link.url) {
            // 링크 구간의 시작(기호 포함)을 줄 안 위치로 적어 둔다.
            let span = line.spans.first { span in
                if case .link = span.kind { span.contentRange.location - line.start == link.location } else { false }
            }
            return .link(line: found.line, offset: (span?.range.location ?? line.start + link.location) - line.start, url: url)
        }
        return nil
    }

    /// 그 줄 왼쪽 칸 그림(체크박스, 꺾쇠)의 가운데. 텍스트 뷰 좌표.
    func gutterPoint(forLine line: Int) -> CGPoint? {
        guard document.lines.indices.contains(line) else { return nil }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        guard let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: document.lines[line].start),
              let fragment = layoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment,
              let gutter = fragment.gutterRect else { return nil }
        let origin = textView.textContainerOrigin
        let frame = fragment.layoutFragmentFrame
        return CGPoint(
            x: origin.x + frame.minX + gutter.minX + style.checkSize / 2,
            y: origin.y + frame.minY + gutter.midY
        )
    }

    /// 그 줄 글자 영역 안의 한 점(첫 줄 조각의 가운데 높이, 글자 시작 바로 뒤). 텍스트 뷰 좌표.
    func textPoint(forLine line: Int) -> CGPoint? {
        guard document.lines.indices.contains(line) else { return nil }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        guard let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: document.lines[line].start),
              let fragment = layoutManager.textLayoutFragment(for: location),
              let first = fragment.textLineFragments.first else { return nil }
        let origin = textView.textContainerOrigin
        let frame = fragment.layoutFragmentFrame
        let bounds = first.typographicBounds
        return CGPoint(x: origin.x + frame.minX + bounds.minX + 1, y: origin.y + frame.minY + bounds.midY)
    }

    func pointer(at point: CGPoint, selectingText: Bool) -> NSCursor {
        if isOverScheduleButton(point) || isOverCopyButton(point) { return .arrow }
        switch hit(at: point) {
        case .link: return blockSelection == nil && !selectingText ? .pointingHand : .iBeam
        case .checkbox, .chevron: return .arrow
        case nil: return .iBeam
        }
    }

    func registerLinkCursorRects() {
        guard blockSelection == nil, !textView.selectingWithMouse else { return }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let viewport = layoutManager.textViewportLayoutController.viewportRange
        layoutManager.enumerateTextLayoutFragments(from: viewport?.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard frame.minY <= visible.maxY else { return false }
            if frame.maxY >= visible.minY, let paragraph = fragment as? MarkdownLayoutFragment,
               FoldState.foldRoot(of: paragraph.row, in: self.document, folded: self.folded) == nil {
                for rect in paragraph.openableLinkRects {
                    let clipped = rect.offsetBy(dx: frame.minX, dy: frame.minY).intersection(visible)
                    if !clipped.isEmpty { self.textView.addCursorRect(clipped, cursor: .pointingHand) }
                }
            }
            return true
        }
    }

    /// 본문에서 클릭 동작을 처리하는 자리.
    func isInteractive(at point: CGPoint) -> Bool {
        isOverScheduleButton(point) || hit(at: point) != nil || isOverCopyButton(point)
    }

    private func isOverScheduleButton(_ point: CGPoint) -> Bool {
        scheduleButtons.values.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    /// 코드 블록의 복사 버튼이 보이고(블록에 마우스가 올라가 있다) 그 점이 버튼 위인지. 텍스트 뷰 좌표.
    func isOverCopyButton(_ point: CGPoint) -> Bool {
        hoveredCodeBlock != nil && !copyButton.isHidden && copyButton.frame.contains(point)
    }

    /// - Returns: 눌린 것을 처리했으면 `true`(텍스트 뷰는 커서를 옮기지 않는다).
    func handleMouseDown(at point: CGPoint) -> Bool {
        guard let hit = hit(at: point) else { return false }
        switch hit {
        case .checkbox(let line):
            guard !textView.hasMarkedText() else { return true }
            setHoveredCheckbox(nil)
            apply(EditorCommands.toggleDone(document, lines: line...line, selection: clamped(textView.selectedRange())))
            setHoveredCheckbox(line)
        case .chevron(let line):
            toggleFold(line: line)
        case .link(_, _, let url):
            if let onOpenLink { onOpenLink(url) } else { NSWorkspace.shared.open(url) }
        }
        return true
    }

    func toggleFold(line: Int) {
        guard document.lines.indices.contains(line), document.lines[line].kind.isToggle else { return }
        if folded.contains(line) {
            changeUserFolds(folded.subtracting([line]))
        } else {
            // 커서가 접히는 줄 안에 있으면 토글 제목 끝으로 옮긴다.
            let selection = clamped(textView.selectedRange())
            let title = document.lines[line]
            let titleEnd = document.lines[document.blockLines(at: line).upperBound].end
            let subtreeEnd = title.subtreeEnd < document.lines.count ? document.lines[title.subtreeEnd].start : document.length + 1
            if NSMaxRange(selection) > titleEnd, selection.location < subtreeEnd {
                setSelection(NSRange(location: titleEnd, length: 0))
            }
            changeUserFolds(folded.union([line]))
        }
    }

    /// - Returns: 누를 수 있는 것(복사 버튼 포함) 위면 `true`(화살표 커서).
    func handleMouseMoved(at point: CGPoint) -> Bool {
        let hit = hit(at: point)
        if case .checkbox(let line) = hit { setHoveredCheckbox(line) } else { setHoveredCheckbox(nil) }
        var link: (line: Int, offset: Int)?
        if case .link(let line, let offset, _) = hit { link = (line, offset) }
        if link?.line != hoveredLink?.line || link?.offset != hoveredLink?.offset {
            hoveredLink = link
            refreshStyling()
        }
        var block: ClosedRange<Int>?
        if let found = fragment(at: point) { block = document.lines[found.line].codeBlock }
        // 복사 버튼 위에 있는 동안에는 그 블록을 유지한다.
        if block == nil, hoveredCodeBlock != nil, copyButton.frame.contains(point) { block = hoveredCodeBlock }
        setHoveredCodeBlock(block)
        return hit != nil || isOverCopyButton(point) || isOverScheduleButton(point)
    }

    func setHoveredCheckbox(_ line: Int?) {
        guard line != hoveredCheckbox else { return }
        hoveredCheckbox = line
        if let line, document.lines.indices.contains(line), case .todo(let done) = document.lines[line].kind {
            checkboxHover.update(center: gutterPoint(forLine: line), done: done, style: style, theme: theme)
        } else {
            checkboxHover.update(center: nil, done: false, style: style, theme: theme)
        }
    }

    func handleMouseExited() {
        setHoveredCheckbox(nil)
        if hoveredLink != nil {
            hoveredLink = nil
            refreshStyling()
        }
        setHoveredCodeBlock(nil)
    }

    // MARK: 코드 블록 복사 버튼

    func setHoveredCodeBlock(_ block: ClosedRange<Int>?) {
        guard block != hoveredCodeBlock else { return }
        hoveredCodeBlock = block
        layoutCopyButton()
        copyButton.setVisible(block != nil, duration: Self.reduceMotion ? 0 : theme.motion.duration, timing: theme.motion.timingFunction)
    }

    /// 버튼을 블록의 오른쪽 위에 놓는다.
    func layoutCopyButton() {
        guard let block = hoveredCodeBlock, block.upperBound < document.lines.count else { return }
        let location = document.lines[block.lowerBound].start
        guard let textLocation = contentStorage.location(contentStorage.documentRange.location, offsetBy: location),
              let fragment = layoutManager.textLayoutFragment(for: textLocation) else { return }
        let origin = textView.textContainerOrigin
        let frame = fragment.layoutFragmentFrame
        let top = frame.minY + (fragment.textLineFragments.first?.typographicBounds.minY ?? 0)
        let size = theme.component(.iconButton)
        copyButton.frame = CGRect(
            x: origin.x + textContainer.size.width - style.metrics.copyButtonInset - size,
            y: origin.y + top + style.metrics.copyButtonInset,
            width: size,
            height: size
        )
    }

    /// 블록 안의 코드(``` 줄 제외)를 클립보드에 올린다.
    func copyHoveredCodeBlock() {
        guard let block = hoveredCodeBlock else { return }
        let code = codeText(in: block)
        let pasteboard = codePasteboard
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    func codeText(in block: ClosedRange<Int>) -> String {
        block.filter { document.lines[$0].kind == .code }
            .map { index in
                let line = document.lines[index]
                return document.string(in: NSRange(location: line.start + line.indentLength, length: line.end - line.start - line.indentLength))
            }
            .joined(separator: "\n")
    }
}
