import AppKit
import Theme

/// 가장 가까운 예정과 나머지 건수를 표시하고 예정 편집을 연다.
final class ReminderBadgeView: ClickableView {
    var paletteID: String?
    var onPress: (() -> Void)?

    private let style: PanelStyle
    private let label = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let chip = NSView()
    private let dot = NSView()
    private var fadeTask: Task<Void, Never>?
    private var presentation: ReminderPresentation?
    private var isPointerInside = false

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        chip.wantsLayer = true
        dot.wantsLayer = true
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        countLabel.cell?.usesSingleLineMode = true
        [chip, dot, label, countLabel].forEach(addSubview)
        isHidden = true
        alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

    func apply(_ presentation: ReminderPresentation?, count: Int = 0, animated: Bool) {
        let changed = (self.presentation == nil) != (presentation == nil)
        self.presentation = presentation
        if let presentation {
            label.stringValue = presentation.text ?? ""
            countLabel.stringValue = count > 0 ? "+\(count)" : ""
            toolTip = [presentation.accessibilityLabel, countLabel.stringValue].filter { !$0.isEmpty }.joined(separator: " ")
            setAccessibilityLabel(toolTip)
            refresh()
        }
        if changed {
            fadeTask?.cancel()
            fadeTask = style.fade(self, visible: presentation != nil, animated: animated) { [weak self] in
                if self?.presentation == nil { self?.isHidden = true }
            }
        }
    }

    func refresh() {
        let body = style.theme.nsFont(.body, size: style.theme.tokens.textStyle(.micro).size)
        let feature: [NSFontDescriptor.FeatureKey: Int] = [
            .typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector
        ]
        let descriptor = body.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        label.font = NSFont(descriptor: descriptor, size: body.pointSize) ?? body
        countLabel.font = label.font
        label.textColor = style.theme.noteTextColor(isPointerInside ? .text : .text2, paletteID: paletteID, overlay: isPointerInside ? .hover : chipFill)
        countLabel.textColor = style.theme.noteTextColor(.text3, paletteID: paletteID, overlay: isPointerInside ? .hover : chipFill)
        needsLayout = true
        needsDisplay = true
    }

    var fittingWidth: CGFloat? {
        guard presentation != nil else { return nil }
        let theme = style.theme
        return theme.component(.badgePad) * 2 + theme.component(.badgeDot) + theme.component(.badgeGap)
            + measuredWidth(label) + countWidth
    }

    private func measuredWidth(_ field: NSTextField) -> CGFloat {
        let text = field.attributedStringValue.size().width.rounded(.up)
        let interior = field.cell?.drawingRect(forBounds: bounds) ?? bounds
        return text + max(0, bounds.width - interior.width) + style.theme.space(.sp1)
    }

    private var countWidth: CGFloat {
        countLabel.stringValue.isEmpty ? 0 : measuredWidth(countLabel) + style.theme.component(.badgeGap)
    }

    private var chipFill: ColorToken { style.theme.appearance == .dark ? .surface3 : .surface2 }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        chip.layer?.backgroundColor = style.cgColor(isPointerInside ? .hover : chipFill, in: self)
        chip.layer?.cornerRadius = style.theme.shape(.chipRadius)
        dot.layer?.backgroundColor = style.cgColor(.warn, in: self)
    }

    override func layout() {
        super.layout()
        let theme = style.theme
        let pad = theme.component(.badgePad), side = theme.component(.badgeDot)
        let height = theme.component(.badgeHeight)
        chip.frame = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
        dot.frame = CGRect(x: pad, y: (bounds.height - side) / 2 - theme.component(.badgeDotDrop), width: side, height: side)
        dot.layer?.cornerRadius = side / 2
        let x = dot.frame.maxX + theme.component(.badgeGap)
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: max(0, bounds.width - x - pad - countWidth), height: h)
        countLabel.frame = CGRect(x: label.frame.maxX + theme.component(.badgeGap), y: label.frame.minY,
                                  width: max(0, countWidth - theme.component(.badgeGap)), height: h)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
    }

    // MARK: - 마우스

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        style.crossfade(self)
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
