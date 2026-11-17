import AppKit

/// 입력을 받지 않는 작은 예정 미리 보기. 호출자가 확보한 빈 공간에만 놓는다.
@MainActor public final class DateSuggestionView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let theme: Theme
    public private(set) var message: String?
    public init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        addSubview(label)
        label.lineBreakMode = .byTruncatingTail
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("코드로만 만든다") }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public override var wantsUpdateLayer: Bool { true }
    public override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = theme.nsColor(.surface2).cgColor
        }
        layer?.cornerRadius = theme.shape(.chipRadius)
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 호출자가 글자와 겹치지 않는 자리를 확보한 뒤 place를 부른다.
    public var preferredSize: NSSize {
        NSSize(width: measuredLabelSize.width + theme.space(.sp2) * 2, height: measuredLabelSize.height)
    }
    private var measuredLabelSize: NSSize = .zero

    public func prepare(_ message: String?) {
        self.message = message
        guard let message else { hide(); return }
        label.stringValue = message
        label.font = theme.nsFont(.ui)
        label.textColor = theme.nsColor(.text2)
        label.setAccessibilityLabel(message)
        label.sizeToFit()
        measuredLabelSize = label.frame.size
    }

    public func place(in host: NSView, area: NSRect) {
        guard message != nil, area.width > 0, area.height > 0 else { hide(); return }
        let appearing = superview == nil || isHidden
        if superview !== host { removeFromSuperview(); host.addSubview(self) }
        let pad = theme.space(.sp2)
        let width = min(measuredLabelSize.width + pad * 2, area.width)
        let height = min(measuredLabelSize.height, area.height)
        frame = NSRect(x: area.minX, y: area.minY, width: width, height: height)
        label.frame = NSRect(x: pad, y: (height - measuredLabelSize.height) / 2,
                             width: max(0, width - pad * 2), height: measuredLabelSize.height)
        isHidden = false
        needsDisplay = true
        setAccessibilityElement(true)
        label.setAccessibilityElement(true)
        guard appearing else { return }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : theme.motion.duration
            context.timingFunction = theme.motion.timingFunction
            animator().alphaValue = 1
        }
    }

    public func hide() {
        // 확보한 공간을 돌려주는 순간에는 잔상이 원문 위에 남지 않게 함께 숨긴다.
        isHidden = true
        setAccessibilityElement(false)
        label.setAccessibilityElement(false)
        removeFromSuperview()
    }
}
