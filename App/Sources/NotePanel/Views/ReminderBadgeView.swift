import AppKit
import Theme

/// 상단 줄의 리마인더: 12pt 아이콘과 글자 하나(spec 5.2, 규칙 13). 누르면 리마인더 설정을 연다.
/// 예정, 임박, 지남의 크기와 자리는 같다.
final class ReminderBadgeView: NSView {
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let iconView = NSImageView()
    private let label = InfoLabel()
    private var presentation: ReminderPresentation?

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyDown
        [iconView, label].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    func apply(_ presentation: ReminderPresentation?, animated: Bool) {
        guard presentation != self.presentation else { return }
        if animated { style.crossfade(self) }
        self.presentation = presentation
        refresh()
    }

    func refresh() {
        isHidden = presentation == nil
        guard let presentation else { return }
        let color = style.color(presentation.color)
        iconView.image = style.symbol(presentation.symbolName, size: .iconSmall)
        iconView.contentTintColor = color
        label.isHidden = presentation.text == nil
        label.set(text: presentation.text ?? "", font: style.theme.nsFont(presentation.textStyle), color: color)
        setAccessibilityLabel(["리마인더", presentation.text].compactMap { $0 }.joined(separator: " "))
        needsLayout = true
        updateRinging()
    }

    /// 자리 너비. 리마인더가 없으면 `nil`. 상태가 바뀌어도 같도록 보통 굵기와 굵은 글자 가운데 넓은 쪽으로 잰다.
    var fittingWidth: CGFloat? {
        guard let presentation else { return nil }
        let icon = style.theme.component(.iconSmall)
        guard let text = presentation.text else { return icon }
        return icon + style.theme.component(.iconGap) + textWidth(text)
    }

    private func textWidth(_ text: String) -> CGFloat {
        [TextStyle.ui, .uiStrong]
            .map { (text as NSString).size(withAttributes: [.font: style.theme.nsFont($0)]).width }
            .max()?.rounded(.up) ?? 0
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let icon = style.theme.component(.iconSmall)
        iconView.frame = NSRect(x: 0, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
        let labelX = icon + style.theme.component(.iconGap)
        label.frame = NSRect(x: labelX, y: 0, width: max(0, bounds.width - labelX), height: bounds.height)
        updateRinging()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRinging()
    }

    /// 임박인 동안 종이 흔들린다. "동작 줄이기"가 켜져 있으면 멈춘다(spec 15).
    private func updateRinging() {
        guard let layer = iconView.layer else { return }
        let shouldRing = presentation?.isRinging == true && !style.reducesMotion && window != nil
        if !shouldRing {
            layer.removeAnimation(forKey: BellRing.animationKey)
        } else if layer.animation(forKey: BellRing.animationKey) == nil, layer.bounds.width > 0 {
            layer.add(BellRing.animation(for: layer), forKey: BellRing.animationKey)
        }
    }

    // MARK: - 마우스

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
