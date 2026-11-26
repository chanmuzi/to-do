import AppKit

/// 둥근 바탕은 텍스트 뷰의 배경 그리기에 제공하고 글자와 왼쪽 칸 장식은 TextKit에서 그린다.
nonisolated final class MarkdownLayoutFragment: NSTextLayoutFragment {
    weak var foldDrawing: FoldDrawing?
    var row = 0

    /// 미리 보기가 들어갈 전용 공간. TextKit이 뒤의 모든 글자를 함께 밀어 원문을 덮지 않는다.
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
            width: decoration.gutterWidth,
            height: bounds.height
        )
    }

    /// 문단 안 글자 구간이 차지하는 사각형들(줄마다 하나). 조각 좌표.
    func rects(for range: NSRange) -> [CGRect] {
        lineRects(for: range).map(\.rect)
    }

    private func lineRects(for range: NSRange) -> [(rect: CGRect, wrappedStart: CGFloat?)] {
        contentLines.enumerated().compactMap { index, line in
            let lineRange = line.characterRange
            let part = NSIntersectionRange(range, lineRange)
            guard part.length > 0 else { return nil }
            let bounds = line.typographicBounds
            let x0 = line.locationForCharacter(at: part.location).x
            let x1 = line.locationForCharacter(at: NSMaxRange(part)).x
            let end = x1 > x0 ? x1 : bounds.width
            let rect = CGRect(x: bounds.minX + x0, y: bounds.minY, width: end - x0, height: bounds.height)
            return (rect, index == 0 ? nil : bounds.minX)
        }
    }

    var openableLinkRects: [CGRect] {
        guard let string = paragraphString, decoration?.isCollapsed != true else { return [] }
        var result: [CGRect] = []
        string.enumerateAttribute(.markdownLink, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            if let url = value as? String, LinkPolicy.openableURL(url) != nil { result += rects(for: range) }
        }
        return result
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
        defer { context.restoreGState() }
        context.setAlpha(foldDrawing?.opacity(at: row) ?? 1)

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        drawQuoteBar(decoration, in: context)
        context.restoreGState()

        // TextKit은 고정한 줄 높이의 남는 공간을 모두 글자 위에 둔다. 글자가 줄의 세로 가운데에 오도록
        // 글자만 위로 옮겨 그린다(줄 높이와 줄 위치는 그대로다).
        super.draw(at: CGPoint(x: point.x, y: point.y - textShift(decoration)), in: context)

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        drawGutter(decoration, in: context)
        context.restoreGState()
    }

    /// NSTextView가 선택을 그리기 전에 글자 뒤의 바탕만 칠한다.
    func drawBackground(at origin: CGPoint, in context: CGContext) {
        guard let decoration, !decoration.isCollapsed else { return }
        context.saveGState()
        context.setAlpha(foldDrawing?.opacity(at: row) ?? 1)
        context.translateBy(x: origin.x, y: origin.y)
        drawCodeBox(decoration, in: context)
        drawInlineBackgrounds(decoration, in: context)
        context.restoreGState()
    }

    /// 글자를 위로 옮길 양. 지금 기준선과, 글자를 줄 가운데에 놓았을 때의 기준선의 차이다.
    private func textShift(_ decoration: FragmentDecoration) -> CGFloat {
        guard let font = decoration.lineFont, let line = contentLines.first else { return 0 }
        let bounds = line.typographicBounds
        let centered = bounds.height / 2 + (font.ascender + font.descender) / 2
        return line.glyphOrigin.y - centered
    }

    /// 이 문단이 세로로 차지하는 높이. 문서 끝의 빈 줄 조각(이 조각에 붙어 놓인다)은 넣지 않는다.
    /// 넣으면 인용문 막대가 그 빈 줄까지 이어져 보인다.
    var ownHeight: CGFloat {
        let lines = textLineFragments
        guard lines.count > 1, let last = lines.last, last.characterRange.length == 0 else { return layoutFragmentFrame.height }
        return min(layoutFragmentFrame.height, last.typographicBounds.minY)
    }

    /// 인용문의 왼쪽 막대. 문단의 위아래 끝까지 칠해 이어지는 인용문 줄의 막대가 하나로 보인다.
    private func drawQuoteBar(_ decoration: FragmentDecoration, in context: CGContext) {
        guard decoration.quoteBar else { return }
        let style = decoration.style
        context.setFillColor(style.text3.cgColor)
        let x = decoration.gutterX - layoutFragmentFrame.minX
        context.fill(CGRect(x: x, y: 0, width: style.quoteBarWidth, height: ownHeight))
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
        context.addPath(BoxPath.fill(rect, radius: style.codeBlockRadius, top: box.top, bottom: box.bottom))
        context.setFillColor(style.codeBlockBackground.cgColor)
        context.fillPath()
    }

    /// 형광펜을 먼저, 인라인 코드를 그 위에 그린다(형광펜 안의 코드도 제 상자를 갖는다).
    private func drawInlineBackgrounds(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let string = paragraphString else { return }
        let style = decoration.style
        for key in [NSAttributedString.Key.markdownHighlight, .markdownCodeBox] {
            for (box, background) in inlineBoxes(for: key, in: string) {
                let radius = key == .markdownHighlight ? style.highlightRadius : style.codeRadius
                context.setFillColor(background.color.cgColor)
                let corner = min(radius, box.height / 2, box.width / 2)
                context.addPath(CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil))
                context.fillPath()
            }
        }
    }

    func inlineBoxes(for key: NSAttributedString.Key, in string: NSAttributedString) -> [(CGRect, InlineBackground)] {
        var boxes: [(rect: CGRect, background: InlineBackground)] = []
        string.enumerateAttribute(key, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let background = value as? InlineBackground else { return }
            boxes += backgroundRects(for: range, background: background).map { ($0, background) }
        }
        guard key == .markdownHighlight, boxes.count > 1 else { return boxes }
        // 같은 화면 줄에서 두 색의 여백이 겹치면 중간에서 나눠 반투명 잉크가 두 번 칠해지지 않게 한다.
        boxes.sort { ($0.rect.midY, $0.rect.minX) < ($1.rect.midY, $1.rect.minX) }
        for i in 1..<boxes.count {
            let left = boxes[i - 1].rect, right = boxes[i].rect
            guard left.midY == right.midY, left.maxX > right.minX else { continue }
            let seam = (left.maxX + right.minX) / 2
            boxes[i - 1].rect.size.width = seam - left.minX
            boxes[i].rect = CGRect(x: seam, y: right.minY, width: right.maxX - seam, height: right.height)
        }
        return boxes
    }

    func backgroundRects(for range: NSRange, background: InlineBackground) -> [CGRect] {
        lineRects(for: range).enumerated().map { index, line in
            let rect = line.rect
            let lead = index == 0 ? background.leadShift : 0
            var left = rect.minX + lead - background.padX
            if case .highlight = background.kind, let start = line.wrappedStart { left = max(left, start) }
            return CGRect(x: left, y: rect.midY - background.height / 2 + background.drop,
                          width: rect.maxX + background.padX - left, height: background.height)
        }
    }

    private func drawGutter(_ decoration: FragmentDecoration, in context: CGContext) {
        guard let gutter = decoration.gutter, let rect = gutterRect else { return }
        GutterGlyph.draw(gutter, in: rect, decoration: decoration, context: context,
                         openness: foldDrawing?.frames[row]?.openness)
    }
}
