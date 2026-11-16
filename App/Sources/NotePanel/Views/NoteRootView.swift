import AppKit
import Theme

/// 노트 창의 내용 뷰(spec 5.1): 바탕, 상단 줄, 선, 본문 스크롤, 오른쪽 아래 버튼.
/// 마우스가 창 위에 있는지도 여기서 받는다(spec 19).
final class NoteRootView: NSView {
    let topRow: TopRowView
    let cornerButtons: CornerButtonsView
    let background: NoteBackgroundView
    var onHoverChange: ((Bool) -> Void)?
    /// 배치가 끝난 뒤. 배치 도중에 알게 된 내용 높이를 이때 창에 반영한다.
    var onLayout: (() -> Void)?
    /// 배치하는 중. 이 동안에는 창 틀을 바꾸지 않는다(배치 안에서 다시 배치가 돌면 본문 자리가 어긋난다).
    private(set) var isLayingOut = false

    private let style: PanelStyle
    private let separator = NSView()
    private let scrollView = NSScrollView()

    init(style: PanelStyle, bodyView: NSView) {
        self.style = style
        topRow = TopRowView(style: style)
        cornerButtons = CornerButtonsView(style: style)
        background = NoteBackgroundView(style: style)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        separator.wantsLayer = true
        configureScrollView(bodyView)
        [background, scrollView, separator, topRow, cornerButtons].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    private func configureScrollView(_ bodyView: NSView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // 스크롤 막대는 스크롤할 때만 보인다(spec 16). 자리를 차지하지 않아 본문 너비가 변하지 않는다.
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = bodyView
    }

    /// 상단 줄과 그 아래 선의 높이.
    var chromeHeight: CGFloat {
        style.theme.shape(.chromeHeight) + style.theme.shape(.borderWidth)
    }

    func setHoverControlsAlpha(_ alpha: Double, animated: Bool) {
        if animated {
            style.animate { cornerButtons.animator().alphaValue = alpha }
        } else {
            cornerButtons.alphaValue = alpha
        }
    }

    func refreshTheme() {
        background.refreshTheme()
        topRow.refreshTheme()
        cornerButtons.refreshTheme()
        needsLayout = true
        needsDisplay = true
    }

    /// 지금 마우스가 이 창 위에 있는지. 창을 띄운 직후에는 들어왔다는 알림이 오지 않는다.
    var containsPointer: Bool {
        guard let window, window.isVisible else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    // MARK: - 그리기와 배치

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = style.theme.shape(.windowRadius)
        layer?.borderWidth = style.theme.shape(.borderWidth)
        layer?.borderColor = style.cgColor(.outline, in: self)
        separator.layer?.backgroundColor = style.cgColor(.line, in: self)
    }

    override func layout() {
        super.layout()
        isLayingOut = true
        placeSubviews()
        isLayingOut = false
        onLayout?()
    }

    private func placeSubviews() {
        let theme = style.theme
        let rowHeight = theme.shape(.chromeHeight)
        background.frame = bounds
        topRow.frame = NSRect(x: 0, y: 0, width: bounds.width, height: rowHeight)
        separator.frame = NSRect(x: 0, y: rowHeight, width: bounds.width, height: theme.shape(.borderWidth))
        scrollView.frame = NSRect(
            x: 0, y: chromeHeight, width: bounds.width, height: max(0, bounds.height - chromeHeight)
        )
        placeBody()
        let corner = cornerButtons.preferredSize
        let inset = theme.space(.sp1)
        cornerButtons.frame = NSRect(
            x: bounds.width - inset - corner.width, y: bounds.height - inset - corner.height,
            width: corner.width, height: corner.height
        )
    }

    /// 본문 뷰는 너비만 맞춘다. 높이는 편집기가 내용에 맞춘다.
    private func placeBody() {
        guard let body = scrollView.documentView else { return }
        if body.frame.width != scrollView.contentSize.width {
            body.setFrameSize(NSSize(width: scrollView.contentSize.width, height: body.frame.height))
        }
        // 창이 줄어들 때 텍스트 뷰가 제 높이를 다시 잡으면서 문서의 원점이 위로 밀리는 일이 있다.
        // 보이는 자리는 그대로 두고 원점을 0으로 되돌려, 스크롤 범위가 내용과 맞게 한다.
        let drift = body.frame.origin
        if drift != .zero {
            let clip = scrollView.contentView
            body.setFrameOrigin(.zero)
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.minX - drift.x, y: clip.bounds.minY - drift.y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    // MARK: - 호버

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
