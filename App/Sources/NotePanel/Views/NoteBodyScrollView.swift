import AppKit

/// 편집기가 커서를 드러내며 움직인 거리는 사용자 스크롤과 구분한다.
final class NoteBodyScrollView: NSScrollView {
    private var measuredHeight: CGFloat = 0
    private(set) var fittingHeight = false
    private var scrolling = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        autohidesScrollers = true
        contentView.drawsBackground = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // AppKit은 시스템 설정이나 입력 장치가 바뀌면 새 스타일을 보낸다.
    override var scrollerStyle: NSScroller.Style {
        didSet {
            guard oldValue != scrollerStyle else { return }
            scrolling = false
            updateScroller()
        }
    }

    func update(contentHeight: CGFloat, fittingHeight: Bool) {
        if measuredHeight != contentHeight || fittingHeight { scrolling = false }
        measuredHeight = contentHeight
        self.fittingHeight = fittingHeight
        updateScroller()
    }

    private var canScroll: Bool {
        !fittingHeight && contentSize.height > 0 && measuredHeight > contentSize.height
    }

    private func updateScroller() {
        let show = canScroll && (scrollerStyle == .legacy || scrolling)
        if hasVerticalScroller != show {
            hasVerticalScroller = show
            if show { verticalScroller?.controlSize = .small }
        }
    }

    func beginUserScroll() {
        guard canScroll else { return }
        scrolling = true
        updateScroller()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY != 0 { beginUserScroll() }
        super.scrollWheel(with: event)
    }

    override func scrollToEndOfDocument(_ sender: Any?) {
        beginUserScroll()
        guard let documentView else { return }
        let clip = contentView
        var target = clip.bounds
        target.origin.y = documentView.isFlipped ? clip.documentRect.maxY - target.height : clip.documentRect.minY
        clip.scroll(to: clip.constrainBoundsRect(target).origin)
        reflectScrolledClipView(clip)
    }

    /// 커서 이동이나 같은 높이의 편집도 오버레이를 다시 켜지 않게 한다.
    @objc func endUserScroll(_ notification: Notification) {
        scrolling = false
        updateScroller()
    }
}
