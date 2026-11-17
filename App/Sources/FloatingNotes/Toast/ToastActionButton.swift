import AppKit
import Theme

/// 짧은 알림의 동작 하나("되돌리기", "열기"). 테두리 없는 글자 단추이고 마우스를 올리면 `hover` 상자가 깔린다
/// (규칙 9, 10). 누름은 언제나 이 뷰가 통째로 받고, 키 창이 아니어도 첫 누름에 동작한다.
final class ToastActionButton: NSView {
    var onPress: (() -> Void)?

    private let theme: Theme
    private let label = NSTextField(labelWithString: "")
    private var isPointerInside = false

    init(theme: Theme, title: String) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        label.stringValue = title
        label.font = theme.nsFont(.body, size: theme.tokens.textStyle(.title).size, weight: theme.tokens.textStyle(.title).weight)
        label.textColor = theme.nsColor(.text)
        // 옆의 안내 글(`ToastView`)과 같은 한 줄 모드로 그린다. 모드가 다르면 같은 자리에 두어도 글자가 2pt 높게 그려진다.
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    var title: String { label.stringValue }

    /// 글자 너비에 좌우 `sp-2`, 높이 `ctl-h`.
    var preferredSize: NSSize {
        NSSize(
            width: (label.intrinsicContentSize.width + theme.space(.sp2) * 2).rounded(.up),
            height: theme.component(.controlHeight)
        )
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = theme.shape(.chipRadius)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isPointerInside ? theme.nsColor(.hover).cgColor : CGColor.clear
        }
        label.textColor = theme.nsColor(.text)
    }

    override func layout() {
        super.layout()
        let size = label.intrinsicContentSize
        label.frame = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width.rounded(.up), height: size.height.rounded(.up)
        )
    }

    // MARK: - 마우스

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : theme.motion.duration
            context.timingFunction = theme.motion.timingFunction
            context.allowsImplicitAnimation = true
            updateLayer()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
