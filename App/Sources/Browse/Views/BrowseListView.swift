import AppKit

/// 목록: 줄을 위에서부터 쌓는다. 고른 줄 하나에 `hover` 바탕이 깔리고, 마우스를 올린 줄이 고른 줄이 된다(spec 8).
final class BrowseListView: NSView {
    private let style: BrowseStyle
    private(set) var entryViews: [BrowseEntryView] = []
    private(set) var entries: [BrowseEntry] = []
    private(set) var selectedIndex: Int?
    private var trackingArea: NSTrackingArea?

    /// 마우스가 줄 위로 옮겨 갔다(그 줄을 고른다).
    var onHover: ((Int) -> Void)?
    /// 줄을 눌렀다.
    var onActivate: ((Int) -> Void)?

    init(style: BrowseStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
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
        views.forEach(addSubview)
        selectedIndex = nil
        select(selected, animated: false)
        frame.size.height = contentHeight
        needsLayout = true
    }

    var contentHeight: CGFloat { entryViews.reduce(0) { $0 + $1.height } }

    func select(_ index: Int?, animated: Bool) {
        guard index != selectedIndex else { return }
        if let selectedIndex, entryViews.indices.contains(selectedIndex) {
            entryViews[selectedIndex].setHighlighted(false, animated: animated)
        }
        selectedIndex = index
        guard let index, entryViews.indices.contains(index) else { return }
        entryViews[index].setHighlighted(true, animated: animated)
        scrollToVisible(entryViews[index].frame)
    }

    func refreshTheme() {
        entryViews.forEach { $0.refreshTheme() }
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for view in entryViews {
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: view.height)
            y += view.height
        }
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
        super.hitTest(point) == nil ? nil : self
    }

    private func selectableIndex(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return entryViews.indices.first { entries[$0].isSelectable && entryViews[$0].frame.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        if let index = selectableIndex(at: event), index != selectedIndex { onHover?(index) }
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    /// 누른 줄에서 손을 뗐을 때 연다.
    override func mouseUp(with event: NSEvent) {
        if let index = selectableIndex(at: event) { onActivate?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        if let index = selectableIndex(at: event), index != selectedIndex { onHover?(index) }
    }

    /// 눌러도 검색 칸의 포커스를 가져오지 않는다.
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
