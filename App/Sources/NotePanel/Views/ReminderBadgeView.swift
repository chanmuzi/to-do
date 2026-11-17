import AppKit
import Theme

/// 상단 줄의 리마인더: 12pt 아이콘과 글자 하나(spec 5.2, 규칙 13). 누르면 리마인더 설정을 연다.
/// 예정, 임박, 지남의 크기와 자리는 같다.
final class ReminderBadgeView: ClickableView {
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let iconView = NSImageView()
    private let failureView = NSImageView()
    private let label = InfoLabel()
    private var presentation: ReminderPresentation?
    /// 다 사라진 뒤 숨기는 일(`dur` 뒤). 그사이 다시 나타나면 취소한다.
    private var fadeSettle: Task<Void, Never>?

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleNone
        [iconView, label, failureView].forEach(addSubview)
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
        let color = style.color(presentation.color)
        iconView.image = style.symbol(presentation.symbolName, size: .iconSmall)
        iconView.contentTintColor = color
        label.isHidden = presentation.text == nil
        label.set(text: presentation.text ?? "", font: style.theme.nsFont(presentation.textStyle), color: color)
        setAccessibilityLabel(presentation.accessibilityLabel)
        failureView.isHidden = !presentation.syncFailed
        failureView.image = style.symbol("exclamationmark.circle", size: .iconSmall)
        failureView.contentTintColor = style.color(.text3)
        toolTip = presentation.syncFailed ? "연동 실패, 앱에 저장됨" : nil
        needsLayout = true
        updateRinging()
    }

    /// 자리 너비. 리마인더가 없으면 `nil`. 상태가 바뀌어도 같도록 보통 굵기와 굵은 글자 가운데 넓은 쪽으로 잰다.
    var fittingWidth: CGFloat? {
        guard let presentation else { return nil }
        let icon = style.theme.component(.iconSmall)
        let failure = presentation.syncFailed ? icon + style.theme.component(.iconGap) : 0
        guard let text = presentation.text else { return icon + failure }
        return icon + style.theme.component(.iconGap) + textWidth(text) + failure
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
        iconView.frame = style.theme.symbolFrame(
            NSRect(x: 0, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
        )
        let labelX = icon + style.theme.component(.iconGap)
        let failure = presentation?.syncFailed == true ? icon + style.theme.component(.iconGap) : 0
        label.frame = NSRect(x: labelX, y: 0, width: max(0, bounds.width - labelX - failure), height: bounds.height)
        failureView.frame = NSRect(x: bounds.width - icon, y: (bounds.height - icon) / 2, width: icon, height: icon)
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
            layer.add(
                BellRing.animation(for: layer, motion: style.theme.motion.bell), forKey: BellRing.animationKey
            )
        }
    }

    // MARK: - 마우스

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
