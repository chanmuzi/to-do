import AppKit

/// 줄 왼쪽 칸의 그림: 체크박스, 글머리표, 토글 꺾쇠. 칸의 왼쪽 끝에 붙이고 세로 가운데에 둔다.
nonisolated enum GutterGlyph {
    static func draw(_ glyph: FragmentDecoration.Gutter, in gutter: CGRect, decoration: FragmentDecoration, context: CGContext, openness: Double? = nil) {
        let style = decoration.style
        switch glyph {
        case .checkbox(let done):
            if style.checkboxStyle == .bracket {
                drawBracket(done: done, in: gutter, style: style, context: context)
            } else {
                drawCheckbox(done: done, in: gutter, style: style, context: context)
            }
        case .bullet(let shape):
            drawBullet(shape, in: gutter, style: style, context: context)
        case .chevron(let open):
            drawChevron(openness: openness ?? (open ? 1 : 0), size: decoration.chevronSize, in: gutter, style: style, context: context)
        }
    }

    /// 뒤집힌(위가 0인) 좌표에서 글자를 그린다.
    static func draw(_ text: NSAttributedString, at point: CGPoint, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCheckbox(done: Bool, in gutter: CGRect, style: EditorStyle, context: CGContext) {
        let size = style.checkSize
        let box = CGRect(x: gutter.minX, y: gutter.midY - size / 2, width: size, height: size)
        if done {
            context.addPath(CGPath(roundedRect: box, cornerWidth: style.checkRadius, cornerHeight: style.checkRadius, transform: nil))
            context.setFillColor(style.text3.cgColor)
            context.fillPath()
            // 24 단위 캔버스의 체크 그림(M5 12.5 l4.5 4.5 L19 7)을 줄여 상자 가운데에 놓는다.
            let scale = style.metrics.checkmarkSize / 24
            let origin = CGPoint(x: box.midX - style.metrics.checkmarkSize / 2, y: box.midY - style.metrics.checkmarkSize / 2)
            strokePolyline(
                [CGPoint(x: 5, y: 12.5), CGPoint(x: 9.5, y: 17), CGPoint(x: 19, y: 7)],
                scale: scale, origin: origin, width: style.metrics.checkmarkStroke, color: style.surface, context: context
            )
        } else {
            let stroke = style.metrics.glyphStroke
            let inset = box.insetBy(dx: stroke / 2, dy: stroke / 2)
            let radius = max(0, style.checkRadius - stroke / 2)
            context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setStrokeColor(style.text2.cgColor)
            context.setLineWidth(stroke)
            context.strokePath()
        }
    }

    private static func drawBracket(done: Bool, in gutter: CGRect, style: EditorStyle, context: CGContext) {
        let text = NSAttributedString(string: done ? "[x]" : "[ ]", attributes: [
            .font: style.inlineCode,
            .foregroundColor: done ? style.text3 : style.text2,
        ])
        draw(text, at: CGPoint(x: gutter.minX, y: gutter.midY - text.size().height / 2), context: context)
    }

    private static func drawBullet(_ shape: Int, in gutter: CGRect, style: EditorStyle, context: CGContext) {
        let x = gutter.minX + style.metrics.bulletInset
        switch shape {
        case 0:
            let d = style.metrics.bulletDot
            context.setFillColor(style.text.cgColor)
            context.fillEllipse(in: CGRect(x: x, y: gutter.midY - d / 2, width: d, height: d))
        case 1:
            let d = style.metrics.bulletDot
            let stroke = style.metrics.glyphStroke
            context.setStrokeColor(style.text.cgColor)
            context.setLineWidth(stroke)
            context.strokeEllipse(in: CGRect(x: x, y: gutter.midY - d / 2, width: d, height: d).insetBy(dx: stroke / 2, dy: stroke / 2))
        default:
            let s = style.metrics.bulletSquare
            context.setFillColor(style.text2.cgColor)
            context.fill(CGRect(x: x, y: gutter.midY - s / 2, width: s, height: s))
        }
    }

    private static func drawChevron(openness: Double, size: CGFloat, in gutter: CGRect, style: EditorStyle, context: CGContext) {
        // 24 단위 캔버스의 꺾쇠. 접힘은 오른쪽(M9.5 6 l6 6 -6 6), 펼침은 아래.
        let points = [CGPoint(x: 9.5, y: 6), CGPoint(x: 15.5, y: 12), CGPoint(x: 9.5, y: 18)]
        // 꺾쇠는 체크박스와 같은 크기의 자리 가운데에 놓인다.
        let origin = CGPoint(x: gutter.minX + (style.checkSize - style.metrics.chevronSize) / 2, y: gutter.midY - size / 2)
        context.saveGState()
        defer { context.restoreGState() }
        let center = CGPoint(x: origin.x + size / 2, y: gutter.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: openness * .pi / 2)
        context.translateBy(x: -center.x, y: -center.y)
        strokePolyline(points, scale: size / 24, origin: origin, width: style.metrics.chevronStroke, color: style.text2, context: context)
    }

    private static func strokePolyline(
        _ points: [CGPoint], scale: CGFloat, origin: CGPoint, width: CGFloat, color: NSColor, context: CGContext
    ) {
        let scaled = points.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) }
        context.addLines(between: scaled)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}

/// 코드 블록 상자의 경로. 블록이 여러 문단에 걸치므로 문단마다 자기 몫만 그린다.
nonisolated enum BoxPath {
    static func fill(_ rect: CGRect, radius: CGFloat, top: Bool, bottom: Bool) -> CGPath {
        outline(rect, radius: radius, top: top, bottom: bottom, closed: true)
    }

    private static func outline(_ r: CGRect, radius: CGFloat, top: Bool, bottom: Bool, closed: Bool) -> CGPath {
        let path = CGMutablePath()
        let topRadius = top ? radius : 0
        let bottomRadius = bottom ? radius : 0
        // 왼쪽 아래에서 위로, 위를 지나 오른쪽 아래로.
        path.move(to: CGPoint(x: r.minX, y: r.maxY - bottomRadius))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + topRadius))
        if top {
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + topRadius, y: r.minY), radius: topRadius)
            path.addLine(to: CGPoint(x: r.maxX - topRadius, y: r.minY))
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + topRadius), radius: topRadius)
        } else if closed {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        } else {
            path.move(to: CGPoint(x: r.maxX, y: r.minY))
        }
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))
        if bottom {
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - bottomRadius, y: r.maxY), radius: bottomRadius)
            path.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bottomRadius), radius: bottomRadius)
        } else if closed {
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        if closed { path.closeSubpath() }
        return path
    }
}
