import AppKit
import Theme

/// 캡처 바 오른쪽의 표시 하나(스페이스, 리마인더): 아이콘(`text-3`)과 글자(D2Coding `fs-ui`, `text-2`).
final class CaptureBadgeView: NSView {
    struct Content: Hashable {
        var symbolName: String?
        var symbolSize: ComponentToken
        var text: String
        var accessibilityLabel: String
        /// 지난 때라 걸리지 않는 리마인더: 글자를 `text-3`로 흐리게 하고 가운데 줄을 긋는다.
        var isStruckOut = false
    }

    private let style: CaptureStyle
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private(set) var content: Content?
    /// 보여야 하는지(움직이는 중이어도 가려는 쪽).
    private var isShown = false
    /// 다 흐려진 뒤 자리를 비우는 일.
    private var vacate: Task<Void, Never>?

    init(style: CaptureStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        iconView.imageScaling = .scaleNone
        label.lineBreakMode = .byTruncatingTail
        [iconView, label].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 내용을 바꾼다. 나타나고 사라지는 것은 알파로 `dur` 동안(규칙 8). 사라질 때는 마지막 내용을 그대로 둔 채 흐려진다.
    func apply(_ newContent: Content?, animated: Bool) {
        vacate?.cancel()
        vacate = nil
        isShown = newContent != nil
        if let newContent {
            content = newContent
            refresh()
        }
        let alpha: CGFloat = isShown ? 1 : 0
        guard animated, alpha != alphaValue else {
            alphaValue = alpha
            if !isShown { vacateSlot() }
            return
        }
        style.animate { animator().alphaValue = alpha }
        // 다 흐려진 뒤에 자리를 비운다. 움직임이 끝났다는 알림이 아니라 `dur` 뒤의 시계로 한다.
        if !isShown { vacate = style.afterTransition { [weak self] in self?.vacateSlot() } }
    }

    /// 사라진 표시의 내용을 버리고 자리를 비운다. 그사이 다시 나타났으면 두지 않는다.
    private func vacateSlot() {
        vacate = nil
        guard !isShown, content != nil else { return }
        alphaValue = 0
        content = nil
        superview?.needsLayout = true
    }

    func refresh() {
        guard let content else { return }
        iconView.image = content.symbolName.flatMap { style.symbol($0, size: content.symbolSize) }
        iconView.contentTintColor = style.color(.text3)
        iconView.isHidden = iconView.image == nil
        let font = style.theme.nsFont(.ui)
        label.font = font
        label.textColor = style.color(content.isStruckOut ? .text3 : .text2)
        if content.isStruckOut {
            label.attributedStringValue = NSAttributedString(string: content.text, attributes: [
                .font: font, .foregroundColor: style.color(.text3),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: style.color(.text3),
            ])
        } else {
            label.stringValue = content.text
        }
        setAccessibilityLabel(content.accessibilityLabel)
        needsLayout = true
    }

    private var iconSide: CGFloat {
        guard let content, !iconView.isHidden else { return 0 }
        return style.theme.component(content.symbolSize)
    }

    /// 자리 너비. 내용이 없으면 0.
    var fittingWidth: CGFloat {
        guard content != nil else { return 0 }
        let gap = iconSide > 0 ? style.theme.component(.iconGap) : 0
        return iconSide + gap + style.textWidth(of: label)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let side = iconSide
        iconView.frame = style.theme.symbolFrame(
            NSRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        )
        let labelX = side > 0 ? side + style.theme.component(.iconGap) : 0
        label.frame = style.labelFrame(
            label, textX: labelX, textWidth: bounds.width - labelX, centeredIn: bounds.height
        )
    }
}
