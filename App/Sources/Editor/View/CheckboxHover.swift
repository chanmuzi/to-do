import AppKit
import Theme

/// 글자와 클릭 처리는 아래의 텍스트 뷰에 맡긴다.
final class CheckboxHover: NSView {
    private var style: EditorStyle?
    private var done = false
    private var radius: CGFloat = 0
    private var fill: NSColor = .clear
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(center: CGPoint?, done: Bool, style: EditorStyle, theme: Theme) {
        let visible = center != nil
        if let center {
            self.done = done
            self.style = style
            let inset = theme.space(.sp1)
            radius = theme.shape(.controlRadius)
            fill = theme.rgba(.hover).nsColor
            let side = min(style.body.lineHeight, style.checkSize + inset * 2)
            frame = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            needsDisplay = true
        }
        let alpha: CGFloat = visible ? 1 : 0
        guard alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup {
            $0.duration = EditorController.reduceMotion ? 0 : theme.motion.duration
            $0.timingFunction = theme.motion.timingFunction
            animator().alphaValue = alpha
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        let box = CGRect(x: bounds.midX - style.checkSize / 2, y: bounds.midY - style.checkSize / 2,
                         width: style.checkSize, height: style.checkSize)
        let halo = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if done {
            halo.append(NSBezierPath(roundedRect: box, xRadius: style.checkRadius, yRadius: style.checkRadius))
            halo.windingRule = .evenOdd
        }
        fill.setFill()
        halo.fill()
        if !done && style.checkboxStyle != .bracket {
            let stroke = style.metrics.glyphStroke
            let r = max(0, style.checkRadius - stroke / 2)
            let border = NSBezierPath(roundedRect: box.insetBy(dx: stroke / 2, dy: stroke / 2), xRadius: r, yRadius: r)
            border.lineWidth = stroke
            style.text.setStroke()
            border.stroke()
        }
    }
}
