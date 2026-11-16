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

    init(style: CaptureStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        iconView.imageScaling = .scaleProportionallyDown
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
        if let newContent {
            content = newContent
            refresh()
        }
        let alpha: CGFloat = newContent == nil ? 0 : 1
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, newContent == nil, self.alphaValue == 0 else { return }
            self.content = nil
            self.superview?.needsLayout = true
        }
        guard animated, alpha != alphaValue else {
            alphaValue = alpha
            finish()
            return
        }
        style.animate({ animator().alphaValue = alpha }, completion: finish)
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
        iconView.frame = NSRect(x: 0, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let labelX = side > 0 ? side + style.theme.component(.iconGap) : 0
        label.frame = style.labelFrame(
            label, textX: labelX, textWidth: bounds.width - labelX, centeredIn: bounds.height
        )
    }
}
