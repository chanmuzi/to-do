import AppKit
import Theme

/// 노트 창의 바탕(spec 5.1, 19): 뒤 배경 흐림 위에 `surface`를 `opacity` 알파로 깔고,
/// 노트 색이 있으면 팔레트 색을 `tint-mix` 알파로 한 장 더 얹는다. 포커스와 상관없이 같다(규칙 5).
final class NoteBackgroundView: NSView {
    private let style: PanelStyle
    private let effectView = NSVisualEffectView()
    private let surfaceView = NSView()
    private let tintView = NSView()
    private var paletteID: String?

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        for view in [effectView, surfaceView, tintView] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }
        surfaceView.wantsLayer = true
        tintView.wantsLayer = true
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    func setPalette(_ id: String?, animated: Bool) {
        guard id != paletteID else { return }
        paletteID = id
        if animated {
            style.animate { updateLayer() }
        } else {
            needsDisplay = true
        }
    }

    func refreshTheme() {
        effectView.maskImage = Self.roundedMask(radius: style.theme.shape(.windowRadius))
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let theme = style.theme
        surfaceView.layer?.backgroundColor = style.cgColor(
            style.color(.surface).withAlphaComponent(theme.material.opacity), in: self
        )
        let tint = paletteID.flatMap { theme.tokens.paletteColor(id: $0) }
        tintView.layer?.backgroundColor = tint.map {
            $0.color.withAlpha(theme.material.tintMix).nsColor.cgColor
        } ?? CGColor.clear
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
