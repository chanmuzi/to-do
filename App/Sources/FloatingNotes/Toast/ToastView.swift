import AppKit
import SwiftUI
import Theme

/// 짧은 알림의 모습(D-041): 한 줄의 글과 동작 하나. 흑백이고, 바탕은 캡처 바와 같다(뒤 배경 흐림 위에
/// `surface`를 `opacity`로, `outline` 테두리, 모서리 `r-window`). 높이 `toast-h`, 좌우 `toast-pad`,
/// 글과 동작 사이 `toast-gap`.
final class ToastView: NSView {
    let actionButton: ToastActionButton
    private let theme: Theme
    private let effectView = NSVisualEffectView()
    private let surfaceView = NSView()
    private let label = NSTextField(labelWithString: "")

    private let faceView: NSView?
    private let tint: CAGradientLayer?
    private var faceWidth: CGFloat { faceView == nil ? 0 : theme.component(.agentFaceMedium) + theme.space(.sp2) }

    init(theme: Theme, message: String, actionTitle: String, face: AgentFaceState? = nil, working: Bool = false) {
        faceView = face.map { NSHostingView(rootView: AgentFace(theme: theme, state: $0, size: .medium)) }
        tint = working ? CAGradientLayer() : nil
        self.theme = theme
        actionButton = ToastActionButton(theme: theme, title: actionTitle)
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: theme.shape(.windowRadius))
        surfaceView.wantsLayer = true
        if let tint { surfaceView.layer?.addSublayer(tint) }
        label.stringValue = message
        label.font = theme.nsFont(.body, size: theme.tokens.textStyle(.title).size)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        [effectView, surfaceView, label, actionButton].forEach(addSubview)
        if let faceView { addSubview(faceView) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    var message: String { label.stringValue }

    /// 글과 동작이 다 보이는 크기. 너비는 `maxWidth`를 넘지 않고, 넘치면 글이 말줄임표로 줄어든다.
    func fittingSize(maxWidth: CGFloat) -> NSSize {
        let padding = theme.component(.toastPadding)
        let natural = padding * 2 + faceWidth + messageSize.width
            + theme.component(.toastGap) + actionButton.preferredSize.width
        return NSSize(width: min(natural, maxWidth), height: theme.component(.toastHeight))
    }

    /// 안내 글을 다 그리는 크기(`cellSize`). `intrinsicContentSize`는 실제보다 좁게 나온다(`ToastActionButton.labelSize`).
    private var messageSize: NSSize {
        let size = label.cell?.cellSize ?? label.intrinsicContentSize
        return NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// 안내 글과 동작 글자의 기준선(이 뷰의 위에서). 둘은 같아야 한다.
    var baselines: (message: CGFloat, action: CGFloat) {
        (label.frame.minY + label.firstBaselineOffsetFromTop, actionButton.frame.minY + actionButton.labelBaselineFromTop)
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = surfaceView.layer else { return }
        layer.cornerRadius = theme.shape(.windowRadius)
        layer.borderWidth = theme.shape(.borderWidth)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tint?.colors = [ColorToken.surface, .surface, .surface].map { theme.nsColor($0).cgColor }
            tint?.startPoint = .zero
            tint?.endPoint = CGPoint(x: 1, y: 1)
            tint?.cornerRadius = theme.shape(.windowRadius)
            layer.borderColor = theme.nsColor(.outline).cgColor
            layer.backgroundColor = theme.nsColor(.surface).withAlphaComponent(theme.material.opacity).cgColor
        }
        label.textColor = theme.nsColor(.text)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        surfaceView.frame = bounds
        let padding = theme.component(.toastPadding)
        tint?.frame = surfaceView.bounds
        let size = theme.component(.agentFaceMedium)
        faceView?.frame = NSRect(x: padding, y: (bounds.height - size) / 2, width: size, height: size)
        let button = actionButton.preferredSize
        actionButton.frame = NSRect(
            x: bounds.width - padding + theme.space(.sp2) - button.width,
            y: ((bounds.height - button.height) / 2).rounded(), width: button.width, height: button.height
        )
        actionButton.layoutSubtreeIfNeeded()
        let labelHeight = messageSize.height
        let labelEnd = actionButton.frame.minX + theme.space(.sp2) - theme.component(.toastGap)
        // 안내 글은 동작 글자와 같은 기준선에 둔다. 글꼴 굵기가 달라도 글자가 같은 줄에 앉는다.
        let centered = ((bounds.height - labelHeight) / 2).rounded()
        let baselineShift = actionButton.frame.minY + actionButton.labelBaselineFromTop
            - (centered + label.firstBaselineOffsetFromTop)
        label.frame = NSRect(
            x: padding + faceWidth, y: (centered + baselineShift).rounded(),
            width: max(0, labelEnd - padding - faceWidth), height: labelHeight
        )
    }

    /// 뒤 배경 흐림은 레이어 모서리로 잘리지 않는다. 늘어나는 둥근 마스크를 준다.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
