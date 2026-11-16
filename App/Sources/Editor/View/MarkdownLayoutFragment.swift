import AppKit

/// 글자 뒤에 둥근 바탕(형광펜, 인라인 코드, 코드 블록)을 먼저 그리고,
/// 왼쪽 칸의 그림(체크박스, 글머리표, 꺾쇠)과 안내선을 함께 그리는 문단 조각(spec 19).
nonisolated final class MarkdownLayoutFragment: NSTextLayoutFragment {
    private lazy var paragraphString: NSAttributedString? = (textElement as? NSTextParagraph)?.attributedString

    private(set) lazy var decoration: FragmentDecoration? = {
        guard let string = paragraphString, string.length > 0 else { return nil }
        return string.attribute(.markdownDecoration, at: 0, effectiveRange: nil) as? FragmentDecoration
    }()

    /// 글자가 있는 줄 조각. 문서 끝의 빈 줄 조각은 뺀다.
    private var contentLines: [NSTextLineFragment] {
        let lines = textLineFragments
        let filled = lines.filter { $0.characterRange.length > 0 }
        return filled.isEmpty ? Array(lines.prefix(1)) : filled
    }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.maxX
    }

    // MARK: 위치

    /// 왼쪽 칸(체크박스, 꺾쇠)의 영역. 조각 좌표.
    var gutterRect: CGRect? {
        guard let decoration, decoration.gutter != nil, let first = contentLines.first else { return nil }
        let bounds = first.typographicBounds
        return CGRect(
            x: decoration.gutterX - layoutFragmentFrame.minX,
            y: bounds.minY,
            width: decoration.style.gutter,
            height: bounds.height
        )
    }

    /// 문단 안 글자 구간이 차지하는 사각형들(줄마다 하나). 조각 좌표.
    func rects(for range: NSRange) -> [CGRect] {
        contentLines.compactMap { line in
            let lineRange = line.characterRange
            let part = NSIntersectionRange(range, lineRange)
            guard part.length > 0 else { return nil }
            let bounds = line.typographicBounds
            let x0 = line.locationForCharacter(at: part.location).x
            let x1 = line.locationForCharacter(at: NSMaxRange(part)).x
            let end = x1 > x0 ? x1 : bounds.width
            return CGRect(x: bounds.minX + x0, y: bounds.minY, width: end - x0, height: bounds.height)
        }
    }

    /// 그 점(조각 좌표)에 있는 링크의 주소와 문단 안 위치.
    func link(at point: CGPoint) -> (url: String, location: Int)? {
        guard let string = paragraphString else { return nil }
        var found: (String, Int)?
        string.enumerateAttribute(.markdownLink, in: NSRange(location: 0, length: string.length)) { value, range, stop in
            guard let url = value as? String else { return }
            if rects(for: range).contains(where: { $0.contains(point) }) {
                found = (url, range.location)
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: 그리기

    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        guard decoration != nil else { return base }
        let frame = layoutFragmentFrame
        let whole = CGRect(x: -frame.minX, y: 0, width: max(containerWidth, frame.maxX), height: frame.height)
        return base.union(whole.insetBy(dx: -2, dy: -2))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let decoration else {
            super.draw(at: point, in: context)
            return
        }
        if decoration.isCollapsed { return }

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        drawCodeBox(decoration, in: context)
        drawGuides(decoration, in: context)
        drawInlineBackgrounds(decoration, in: context)
        context.restoreGState()

        // TextKit은 고정한 줄 높이의 남는 공간을 모두 글자 위에 둔다. 글자가 줄의 세로 가운데에 오도록
        // 글자만 위로 옮겨 그린다(줄 높이와 줄 위치는 그대로다).
        super.draw(at: CGPoint(x: point.x, y: point.y - textShift(decoration)), in: context)

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        drawGutter(decoration, in: context)
        drawCount(decoration, in: context)
        context.restoreGState()
    }

    /// 글자를 위로 옮길 양. 지금 기준선과, 글자를 줄 가운데에 놓았을 때의 기준선의 차이다.
    private func textShift(_ decoration: FragmentDecoration) -> CGFloat {
        guard let font = decoration.lineFont, let line = contentLines.first else { return 0 }
        let bounds = line.typographicBounds
        let centered = bounds.height / 2 + (font.ascender + font.descender) / 2 + decoration.centerOffset
        return line.glyphOrigin.y - centered
    }

    /// 가운데에 놓은 글자의 기준선(조각 좌표).
    private func baseline(of line: NSTextLineFragment, _ decoration: FragmentDecoration) -> CGFloat {
        let bounds = line.typographicBounds
        let font = decoration.lineFont ?? decoration.style.body.font
        return bounds.midY + (font.ascender + font.descender) / 2 + decoration.centerOffset
    }

    private func drawGuides(_ decoration: FragmentDecoration, in context: CGContext) {
        guard decoration.guideCount > 0 else { return }
        let style = decoration.style
        context.setFillColor(style.guide.cgColor)
        for level in 0..<decoration.guideCount {
            let x = CGFloat(level) * style.indent + EditorMetrics.guideOffset - layoutFragmentFrame.minX
            context.fill(CGRect(x: x, y: 0, width: style.borderWidth, height: layoutFragmentFrame.height))
        }
    }

    /// 코드 블록 상자에서 이 문단이 차지하는 부분. 조각 좌표.
    var codeBoxRect: CGRect? {
        guard let decoration, decoration.codeBox != nil, let first = contentLines.first else { return nil }
        // 문서 끝의 빈 코드 줄은 이 조각에 붙은 빈 줄 조각이다. 상자를 거기까지 늘린다.
        let lines = decoration.codeBoxCoversExtraLine ? textLineFragments : contentLines
        guard let last = lines.last else { return nil }
        return CGRect(
            x: decoration.codeBoxX - layoutFragmentFrame.minX,
            y: first.typographicBounds.minY,
            width: containerWidth - decoration.codeBoxX,
            height: last.typographicBounds.maxY - first.typographicBounds.minY
        )
    }

    private func drawCodeBox(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let box = decoration.codeBox, let rect = codeBoxRect else { return }
        let style = decoration.style
        let radius = style.codeBlockRadius
        context.addPath(BoxPath.fill(rect, radius: radius, top: box.top, bottom: box.bottom))
        context.setFillColor(style.codeBackground.cgColor)
        context.fillPath()
        context.addPath(BoxPath.border(rect, radius: radius, width: style.borderWidth, top: box.top, bottom: box.bottom))
        context.setStrokeColor(style.codeLine.cgColor)
        context.setLineWidth(style.borderWidth)
        context.strokePath()
    }

    private func drawInlineBackgrounds(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let string = paragraphString else { return }
        let style = decoration.style
        string.enumerateAttribute(.markdownInlineBackground, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let background = value as? InlineBackground else { return }
            for rect in rects(for: range) {
                let box = CGRect(
                    x: rect.minX - background.padX,
                    y: rect.midY - background.height / 2,
                    width: rect.width + background.padX * 2,
                    height: background.height
                )
                switch background.kind {
                case .highlight(let number):
                    context.addPath(CGPath(roundedRect: box, cornerWidth: style.highlightRadius, cornerHeight: style.highlightRadius, transform: nil))
                    context.setFillColor(style.highlightBackground(number).cgColor)
                    context.fillPath()
                case .code:
                    context.addPath(CGPath(roundedRect: box, cornerWidth: style.codeRadius, cornerHeight: style.codeRadius, transform: nil))
                    context.setFillColor(style.codeBackground.cgColor)
                    context.fillPath()
                    let inset = box.insetBy(dx: style.borderWidth / 2, dy: style.borderWidth / 2)
                    let radius = max(0, style.codeRadius - style.borderWidth / 2)
                    context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    context.setStrokeColor(style.codeLine.cgColor)
                    context.setLineWidth(style.borderWidth)
                    context.strokePath()
                }
            }
        }
    }

    private func drawGutter(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let gutter = decoration.gutter, let rect = gutterRect else { return }
        GutterGlyph.draw(gutter, in: rect, style: decoration.style, context: context)
    }

    private func drawCount(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let count = decoration.count, let line = contentLines.last else { return }
        let style = decoration.style
        let bounds = line.typographicBounds
        let x = bounds.minX + line.locationForCharacter(at: decoration.countIndex).x + EditorMetrics.countGap
        let text = NSAttributedString(string: count, attributes: [.font: style.micro, .foregroundColor: style.text3])
        // 제목 글자와 기준선을 맞춘다.
        GutterGlyph.draw(text, at: CGPoint(x: x, y: baseline(of: line, decoration) - style.micro.ascender), context: context)
    }
}
