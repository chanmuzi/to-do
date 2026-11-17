import AppKit
import Theme

/// 상단 줄의 리마인더: 다른 상단 버튼과 같은 크기의 아이콘 하나(spec 5.2, 규칙 13). 누르면 리마인더 설정을 연다.
/// 예정, 임박, 지남의 크기와 자리는 같다.
final class ReminderBadgeView: ClickableView {
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let iconView = NSImageView()
    private let failureView = NSImageView()
    private var presentation: ReminderPresentation?
    private var isPointerInside = false
    /// 다 사라진 뒤 숨기는 일(`dur` 뒤). 그사이 다시 나타나면 취소한다.
    private var fadeSettle: Task<Void, Never>?

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleNone
        [iconView, failureView].forEach(addSubview)
        failureView.imageScaling = .scaleNone
        isHidden = true
        alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 리마인더가 생기거나 없어지면 알파로 `dur` 동안 나타나고 사라진다(규칙 8). 내용만 바뀌면 그 자리에서 넘어간다.
    func apply(_ presentation: ReminderPresentation?, animated: Bool) {
        guard presentation != self.presentation else { return }
        let wasShown = self.presentation != nil
        let isShown = presentation != nil
        if wasShown, isShown, animated { style.crossfade(self) }
        self.presentation = presentation
        refresh()
        guard wasShown != isShown else { return }
        fadeSettle?.cancel()
        fadeSettle = style.fade(self, visible: isShown, animated: animated) { [weak self] in
            guard let self else { return }
            fadeSettle = nil
            // 다 사라졌으면 숨긴다. 움직임이 어디까지 갔든 끝의 값으로 놓는다.
            guard self.presentation == nil else { return }
            alphaValue = 0
            isHidden = true
        }
    }

    /// 리마인더가 없어지면 사라지는 동안 마지막 모습을 그대로 둔다.
    func refresh() {
        guard let presentation else {
            updateRinging()
            return
        }
        let color = style.color(isPointerInside && presentation.color != .warn ? .text : presentation.color)
        iconView.image = style.symbol(presentation.symbolName, size: .iconMedium)
        iconView.contentTintColor = color
        setAccessibilityLabel(presentation.accessibilityLabel)
        failureView.isHidden = !presentation.syncFailed
        failureView.image = style.symbol("exclamationmark.circle", size: .iconSmall)
        failureView.contentTintColor = style.color(.text3)
        toolTip = presentation.accessibilityLabel
        needsLayout = true
        updateRinging()
    }

    /// 시간 글자 없이 고정된 버튼 칸만 차지한다.
    var fittingWidth: CGFloat? {
        guard let presentation else { return nil }
        return style.theme.component(.iconButton) + (presentation.syncFailed
            ? style.theme.component(.iconSmall) + style.theme.component(.iconGap) : 0)
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = style.theme.shape(.chipRadius)
        layer?.backgroundColor = isPointerInside ? style.cgColor(.hover, in: self) : CGColor.clear
    }

    override func layout() {
        super.layout()
        let icon = style.theme.component(.iconMedium)
        let button = style.theme.component(.iconButton)
        iconView.frame = style.theme.symbolFrame(
            NSRect(x: (button - icon) / 2, y: (bounds.height - icon) / 2, width: icon, height: icon)
        )
        let failure = style.theme.component(.iconSmall)
        failureView.frame = NSRect(x: bounds.width - failure, y: (bounds.height - failure) / 2, width: failure, height: failure)
        updateRinging()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        updateRinging()
    }

    /// 임박인 동안 종이 흔들린다. "동작 줄이기"가 켜져 있으면 멈춘다(spec 15).
    private func updateRinging() {
        guard let layer = iconView.layer else { return }
        let shouldRing = presentation?.isRinging == true && !style.reducesMotion && window != nil
        if !shouldRing {
            layer.removeAnimation(forKey: BellRing.animationKey)
        } else if layer.animation(forKey: BellRing.animationKey) == nil, layer.bounds.width > 0 {
            layer.add(
                BellRing.animation(for: layer, motion: style.theme.motion.bell), forKey: BellRing.animationKey
            )
        }
    }

    // MARK: - 마우스

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        style.crossfade(iconView)
        refresh()
        style.animate { updateLayer() }
    }

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
