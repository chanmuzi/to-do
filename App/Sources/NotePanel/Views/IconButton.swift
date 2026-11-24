import AppKit
import SwiftUI
import Theme

/// 테두리 없는 아이콘 버튼(규칙 9, 10). 평소에는 아이콘만 보이고, 마우스를 올리면 `hover` 색 상자가 깔린다.
/// 마우스 모양은 바꾸지 않는다(`ClickableView`가 화살표로 밝힌다).
final class IconButton: ClickableView {
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let iconSize: ComponentToken
    private let imageView = NSImageView()
    private var symbolName: String
    private var tint: ColorToken
    var isSelected = false {
        didSet {
            guard oldValue != isSelected else { return }
            setAccessibilityValue(isSelected ? "켜짐" : "꺼짐")
            refresh()
        }
    }
    private var isPointerInside = false

    private var customGlyph: NSView?

    func showFace(_ state: AgentFaceState = .idle) {
        let glyph = AgentFace(theme: style.theme, state: state)
        if let host = customGlyph as? NSHostingView<AgentFace> { host.rootView = glyph; return }
        let face = NSHostingView(rootView: glyph)
        face.sizingOptions = []
        face.setAccessibilityElement(false)
        imageView.isHidden = true
        customGlyph = face
        addSubview(face)
    }

    init(style: PanelStyle, symbolName: String, iconSize: ComponentToken, label: String, tint: ColorToken = .text2) {
        self.style = style
        self.symbolName = symbolName
        self.iconSize = iconSize
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 아이콘과 평소 색을 바꾼다(핀의 켜짐과 꺼짐).
    func set(symbolName: String, tint: ColorToken, animated: Bool) {
        guard symbolName != self.symbolName || tint != self.tint else { return }
        self.symbolName = symbolName
        self.tint = tint
        if animated { style.crossfade(imageView) }
        refresh()
    }

    /// 테마나 접근성 설정이 바뀌었을 때.
    func refresh() {
        if !symbolName.isEmpty {
            imageView.image = NoteButtonGlyph.image(symbolName, theme: style.theme) ?? style.symbol(symbolName, size: iconSize)
        }
        imageView.contentTintColor = style.color(isPointerInside || isSelected ? .text : tint)
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - 그리기

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = style.theme.shape(.controlRadius)
        layer?.backgroundColor = isSelected ? style.cgColor(.formatActive, in: self) : (isPointerInside ? style.cgColor(.hover, in: self) : CGColor.clear)
    }

    override func layout() {
        super.layout()
        let side = style.theme.component(iconSize)
        customGlyph?.frame = bounds
        imageView.frame = NSRect(
            x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
            width: side, height: side
        )
    }

    /// 버튼 가장자리에서 그림의 가장자리까지(좌우 한쪽). 그림은 버튼 가운데에 제 크기로 놓인다.
    var glyphSideInset: CGFloat {
        let button = style.theme.component(.iconButton)
        let glyph = imageView.image?.size.width ?? style.theme.component(iconSize)
        return max(0, (button - glyph) / 2)
    }

    // MARK: - 마우스

    /// 영역은 한 번만 건다. `.inVisibleRect`라 뷰가 움직이고 커져도 AppKit이 따라 맞춘다. 예전에는 자리가 바뀔
    /// 때마다(창 높이가 움직이는 동안 오른쪽 아래 버튼이 따라 움직인다) 영역을 새로 걸었는데, 마우스가 이미 안에
    /// 있는 채로 새로 건 영역은 들어왔다는 알림을 보내지 않아 그 버튼에만 `hover` 상자가 나타나지 않았다.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    /// 지금 마우스가 이 버튼 위에 있는지 다시 잰다(창이 뜬 직후, 호버로 나타날 때).
    func syncPointerInside() {
        guard let window, window.isVisible, !isHidden else { return setPointerInside(false) }
        setPointerInside(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        style.crossfade(imageView)
        imageView.contentTintColor = style.color(inside || isSelected ? .text : tint)
        style.animate { updateLayer() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard acceptsRelease(at: event.locationInWindow) else { return }
        onPress?()
        // 메뉴가 떴다 닫히면 마우스가 나갔다는 알림이 오지 않을 수 있다.
        if let window, !bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            setPointerInside(false)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
