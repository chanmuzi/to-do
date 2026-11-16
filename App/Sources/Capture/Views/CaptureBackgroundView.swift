import AppKit
import Theme

/// 캡처 바의 바탕(spec 7): 뒤 배경 흐림 위에 `surface`를 `opacity` 알파로 깔고 `outline` 테두리를 두른다.
/// 모서리는 `r-window`. 포커스와 상관없이 같다(규칙 5).
final class CaptureBackgroundView: NSView {
    private let style: CaptureStyle
    private let effectView = NSVisualEffectView()
    private let surfaceView = NSView()

    init(style: CaptureStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        surfaceView.wantsLayer = true
        for view in [effectView, surfaceView] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    func refreshTheme() {
        effectView.maskImage = Self.roundedMask(radius: style.theme.shape(.windowRadius))
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let theme = style.theme
        guard let layer = surfaceView.layer else { return }
        layer.cornerRadius = theme.shape(.windowRadius)
        layer.borderWidth = theme.shape(.borderWidth)
        layer.borderColor = style.cgColor(style.color(.outline), in: self)
        layer.backgroundColor = style.cgColor(
            style.color(.surface).withAlphaComponent(theme.material.opacity), in: self
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
