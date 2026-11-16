import AppKit
import Theme

/// 테두리 없는 아이콘 버튼(규칙 9, 10). 평소에는 아이콘만 보이고, 마우스를 올리면 `hover` 색 상자가 깔린다.
/// 마우스 모양은 바꾸지 않는다.
final class IconButton: NSView {
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let iconSize: ComponentToken
    private let imageView = NSImageView()
    private var symbolName: String
    private var tint: ColorToken
    private var isPointerInside = false

    init(style: PanelStyle, symbolName: String, iconSize: ComponentToken, label: String, tint: ColorToken = .text2) {
        self.style = style
        self.symbolName = symbolName
        self.iconSize = iconSize
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyDown
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
        imageView.image = style.symbol(symbolName, size: iconSize)
        imageView.contentTintColor = style.color(isPointerInside ? .text : tint)
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - 그리기

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = style.theme.shape(.chipRadius)
        layer?.backgroundColor = isPointerInside ? style.cgColor(.hover, in: self) : CGColor.clear
    }

    override func layout() {
        super.layout()
        let side = min(style.theme.component(iconSize), bounds.width, bounds.height)
        imageView.frame = NSRect(
            x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(),
            width: side, height: side
        )
    }

    // MARK: - 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        style.crossfade(imageView)
        imageView.contentTintColor = style.color(inside ? .text : tint)
        style.animate { updateLayer() }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
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
