import AppKit
import Theme

/// 노트 색 칸 하나(spec 5.4, 14). 고른 칸에는 `text` 테두리가 떨어져 붙고, 마우스를 올리면 `text-3` 테두리가 나타난다.
/// 뷰는 테두리 자리까지 포함한 크기다(`outset`만큼 칸보다 크다).
final class SwatchView: NSView {
    var onSelect: (() -> Void)?

    private let style: PanelStyle
    private let fill: NSColor
    private let isSelected: Bool
    private let fillLayer = CALayer()
    private let ringLayer = CALayer()
    private var isPointerInside = false

    /// - Parameter palette: 팔레트 색. `nil`이면 색 없음 칸.
    init(style: PanelStyle, palette: PaletteColor?, isSelected: Bool) {
        self.style = style
        self.isSelected = isSelected
        fill = palette?.color.nsColor ?? style.color(.surface)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(ringLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(palette?.name ?? "색 없음")
        setAccessibilityValue(isSelected ? "고름" : nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override var wantsUpdateLayer: Bool { true }

    /// 칸 바깥으로 테두리가 차지하는 거리: 띄우는 거리와 테두리 두께.
    static func outset(_ style: PanelStyle) -> CGFloat {
        style.theme.component(.swatchRing) * 2
    }

    override func updateLayer() {
        let theme = style.theme
        let outset = Self.outset(style)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds.insetBy(dx: outset, dy: outset)
        fillLayer.cornerRadius = theme.shape(.checkRadius)
        fillLayer.backgroundColor = style.cgColor(fill, in: self)
        fillLayer.borderWidth = theme.shape(.borderWidth)
        fillLayer.borderColor = style.cgColor(.outline, in: self)
        ringLayer.frame = bounds
        ringLayer.cornerRadius = theme.shape(.checkRadius) + outset
        ringLayer.borderWidth = theme.component(.swatchRing)
        ringLayer.borderColor = ringColor
        CATransaction.commit()
    }

    private var ringColor: CGColor {
        if isSelected { return style.cgColor(.text, in: self) }
        return isPointerInside ? style.cgColor(.text3, in: self) : CGColor.clear
    }

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
        isPointerInside = inside
        CATransaction.begin()
        CATransaction.setAnimationDuration(style.transitionDuration)
        CATransaction.setAnimationTimingFunction(style.theme.motion.timingFunction)
        ringLayer.borderColor = ringColor
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect?()
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}
