import AppKit
import Theme

/// 코드 블록 오른쪽 위의 복사 버튼. 블록에 마우스를 올렸을 때만 보인다(자리는 글자 위에 겹친다).
/// 테두리 없는 아이콘 버튼: 아이콘에 올렸을 때만 `hover` 바탕이 나타난다(규칙 10).
final class CodeCopyButton: NSView {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private var iconSide: CGFloat = 0
    private var iconMargin: CGFloat = 0
    private var hoverColor: NSColor = .clear
    private var duration: TimeInterval = 0
    private var timing: CAMediaTimingFunction?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0
        icon.imageScaling = .scaleNone
        addSubview(icon)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("복사")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(theme: Theme, tint: NSColor) {
        iconSide = theme.component(.iconMedium)
        iconMargin = theme.space(.sp1)
        icon.image = theme.symbolImage("doc.on.doc", size: .iconMedium)
        needsLayout = true
        icon.contentTintColor = tint
        hoverColor = theme.rgba(.hover).nsColor
        layer?.cornerRadius = theme.shape(.chipRadius)
        updateBackground(animated: false)
    }

    /// 알파만 바꾼다. 자리는 그대로다(규칙 7, 8).
    func setVisible(_ visible: Bool, duration: TimeInterval, timing: CAMediaTimingFunction) {
        self.duration = duration
        self.timing = timing
        if !visible, isHovered {
            isHovered = false
            updateBackground(animated: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            animator().alphaValue = visible ? 1 : 0
        }
    }

    override func layout() {
        super.layout()
        let size = iconSide + iconMargin * 2
        icon.frame = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard alphaValue > 0 else { return super.mouseDown(with: event) }
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func updateBackground(animated: Bool) {
        let color = (isHovered ? hoverColor : .clear).cgColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? duration : 0)
        if let timing { CATransaction.setAnimationTimingFunction(timing) }
        layer?.backgroundColor = color
        CATransaction.commit()
    }
}
