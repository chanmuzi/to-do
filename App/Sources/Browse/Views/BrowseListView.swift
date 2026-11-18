import AppKit

/// 목록: 줄을 위에서부터 쌓는다. 고른 줄 하나에 `selected` 바탕이 깔리고, 마우스를 올린 줄이 고른 줄이 된다(spec 8).
final class BrowseListView: NSView {
    private let scroll = NSScrollView()
    private let results = FlippedResultsView()
    private var resultCount = 0
    private let style: BrowseStyle
    private(set) var entryViews: [BrowseEntryView] = []
    private(set) var entries: [BrowseEntry] = []
    private(set) var selectedIndex: Int?
    private weak var pressedPin: NSButton?
    private var trackingArea: NSTrackingArea?

    /// 마우스가 줄 위로 옮겨 갔다(그 줄을 고른다).
    var onHover: ((Int) -> Void)?
    /// 줄을 눌렀다.
    var onActivate: ((Int) -> Void)?

    init(style: BrowseStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = results
        addSubview(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 줄을 새로 놓는다. 옛 줄은 그 자리에서 바로 없어진다.
    ///
    /// 목록 전체를 `dur` 동안 겹쳐 넘기지 않는다: 줄의 자리가 달라지므로 옛 줄과 새 줄이 겹쳐 보이는
    /// 잔상이 글자를 칠 때마다 생긴다. 검색 결과는 친 글자와 같은 내용이라 바로 바뀌고,
    /// 움직이는 것은 고른 줄의 바탕과 창 높이뿐이다.
    func setEntries(_ newEntries: [BrowseEntry], views: [BrowseEntryView], selected: Int?) {
        entryViews.forEach { $0.removeFromSuperview() }
        entries = newEntries
        entryViews = views
        resultCount = entries.prefix { entry in
            switch entry { case .note, .header: true; default: false }
        }.count
        for (index, view) in views.enumerated() {
            (index < resultCount ? results : self).addSubview(view)
        }
        scroll.contentView.scroll(to: .zero)
        selectedIndex = nil
        select(selected, animated: false)
        needsLayout = true
        layoutSubtreeIfNeeded()
        revealSelection()
    }

    var contentHeight: CGFloat { entryViews.reduce(0) { $0 + $1.height } }

    var visibleHeight: CGFloat {
        let excess = entries.prefix(resultCount).filter { if case .note = $0 { true } else { false } }.count
            - BrowseContent.recentLimit
        return contentHeight - CGFloat(max(0, excess)) * style.theme.component(.browseRowHeight)
    }

    private func revealSelection() {
        if let index = selectedIndex, index < resultCount { results.scrollToVisible(entryViews[index].frame) }
    }

    func select(_ index: Int?, animated: Bool) {
        guard index != selectedIndex else { return }
        if let selectedIndex, entryViews.indices.contains(selectedIndex) {
            entryViews[selectedIndex].setHighlighted(false, animated: animated)
        }
        selectedIndex = index
        guard let index, entryViews.indices.contains(index) else { return }
        entryViews[index].setHighlighted(true, animated: animated)
        revealSelection()
    }

    func refreshTheme() {
        entryViews.forEach { $0.refreshTheme() }
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let footerHeight = entryViews.dropFirst(resultCount).reduce(CGFloat.zero) { $0 + $1.height }
        let resultHeight = contentHeight - footerHeight
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - footerHeight))
        scroll.hasVerticalScroller = resultHeight > scroll.bounds.height
        results.frame.size = NSSize(width: scroll.contentSize.width, height: resultHeight)
        var y: CGFloat = 0
        for (index, view) in entryViews.enumerated() {
            if index == resultCount { y = scroll.frame.maxY }
            view.frame = NSRect(x: 0, y: y, width: index < resultCount ? results.bounds.width : bounds.width, height: view.height)
            y += view.height
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if scroll.hasVerticalScroller { scroll.scrollWheel(with: event) }
    }

    // MARK: - 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 줄 안의 글자와 아이콘이 마우스를 가로채지 않게 목록이 직접 받는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSScroller { return hit }
        return hit == nil ? nil : self
    }

    private func selectableIndex(at event: NSEvent) -> Int? {
        let local = convert(event.locationInWindow, from: nil)
        return entryViews.indices.first { index in
            let view = entryViews[index]
            guard entries[index].isSelectable, index >= resultCount || scroll.frame.contains(local) else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let index = selectableIndex(at: event) else { clearPinHover(); return }
        if index != selectedIndex { onHover?(index) }
        if let row = entryViews[index] as? BrowseNoteRowView {
            row.setPinHover(row.pin.frame.contains(row.convert(event.locationInWindow, from: nil)))
        }
    }

    private func clearPinHover() {
        if let selectedIndex { (entryViews[selectedIndex] as? BrowseNoteRowView)?.setPinHover(false) }
    }

    override func mouseExited(with event: NSEvent) { clearPinHover() }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    /// 누른 줄에서 손을 뗐을 때 연다.
    override func mouseUp(with event: NSEvent) {
        defer { pressedPin = nil }
        guard let index = selectableIndex(at: event) else { return }
        if let pin = pin(at: event, index: index) {
            if pressedPin === pin { (entryViews[index] as? BrowseNoteRowView)?.onPin?() }
        } else if pressedPin == nil { onActivate?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        pressedPin = nil
        guard let index = selectableIndex(at: event) else { return }
        if index != selectedIndex { onHover?(index) }
        pressedPin = pin(at: event, index: index)
    }

    private func pin(at event: NSEvent, index: Int) -> NSButton? {
        guard let row = entryViews[index] as? BrowseNoteRowView, !row.pin.isHidden,
              row.pin.frame.contains(row.convert(event.locationInWindow, from: nil)) else { return nil }
        return row.pin
    }

    /// 눌러도 검색 칸의 포커스를 가져오지 않는다.
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FlippedResultsView: NSView {
    override var isFlipped: Bool { true }
}
