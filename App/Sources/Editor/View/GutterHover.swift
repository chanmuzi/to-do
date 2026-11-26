import AppKit
import Theme

/// 글자와 클릭 처리는 아래의 텍스트 뷰에 맡긴다.
final class GutterHover: NSView {
    private var style: EditorStyle?
    private var glyph: FragmentDecoration.Gutter?
    private var radius: CGFloat = 0
    private var fill: NSColor = .clear
    private var visible = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(glyph: FragmentDecoration.Gutter, box: CGRect, lineHeight: CGFloat, in textView: NSTextView,
              style: EditorStyle, theme: Theme) {
        // 꺾쇠는 TextKit이 바탕 위에 그려야 접는 도중에도 같은 색으로 회전한다.
        // 체크박스는 미완료 테두리를 진하게 그리므로 글자 앞에 놓는다.
        if case .chevron = glyph {
            guard let parent = textView.superview else { return }
            if superview !== parent { parent.addSubview(self, positioned: .below, relativeTo: textView) }
        } else if superview !== textView {
            textView.addSubview(self)
        }
        self.glyph = glyph
        self.style = style
        radius = theme.shape(.controlRadius)
        fill = theme.rgba(.hover).nsColor
        let side = min(lineHeight, box.width + theme.space(.sp1) * 2)
        let rect = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        frame = textView.convert(rect, to: superview)
        needsDisplay = true
        setVisible(true, theme: theme)
    }

    func setVisible(_ visible: Bool, theme: Theme) {
        guard self.visible != visible else { return }
        self.visible = visible
        let alpha: CGFloat = visible ? 1 : 0
        guard window?.isVisible == true, !EditorController.reduceMotion else {
            alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup {
            $0.duration = theme.motion.duration
            $0.timingFunction = theme.motion.timingFunction
            animator().alphaValue = alpha
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let box = CGRect(x: bounds.midX - style.checkSize / 2, y: bounds.midY - style.checkSize / 2,
                         width: style.checkSize, height: style.checkSize)
        let halo = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if glyph == .checkbox(done: true) {
            halo.append(NSBezierPath(roundedRect: box, xRadius: style.checkRadius, yRadius: style.checkRadius))
            halo.windingRule = .evenOdd
        }
        fill.setFill()
        halo.fill()
        if glyph == .checkbox(done: false) && style.checkboxStyle != .bracket {
            let stroke = style.metrics.glyphStroke
            let r = max(0, style.checkRadius - stroke / 2)
            let border = NSBezierPath(roundedRect: box.insetBy(dx: stroke / 2, dy: stroke / 2), xRadius: r, yRadius: r)
            border.lineWidth = stroke
            style.text.setStroke()
            border.stroke()
        }
    }
}
