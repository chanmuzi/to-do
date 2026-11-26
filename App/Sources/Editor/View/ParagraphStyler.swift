import AppKit

/// 원문 한 줄을 화면에 보일 문단으로 바꾼다. 글자는 건드리지 않고 속성만 얹는다
/// (감출 기호는 글자 크기를 거의 0으로 해서 자리를 없앤다). 그래서 원문과 길이가 늘 같다.
nonisolated enum ParagraphStyler {
    static func display(
        source: NSAttributedString,
        line: MarkdownLine,
        key: LineRenderKey,
        style: EditorStyle,
        scheduleInset: CGFloat = 0
    ) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: source)
        guard out.length > 0 else { return out }
        let builder = Builder(out: out, line: line, key: key, style: style, scheduleInset: scheduleInset)
        if key.isCollapsed {
            builder.collapse()
        } else if key.kind.isCode {
            builder.styleCode()
        } else {
            builder.styleText()
        }
        out.addAttribute(.markdownDecoration, value: builder.decoration, range: NSRange(location: 0, length: 1))
        return out
    }

    /// 닫히지 않은 코드 블록 끝의 빈 줄(문서의 마지막 줄)에 쓰는 문단 모양.
    /// 그 줄은 글자가 없어 문단이 만들어지지 않으므로 텍스트 뷰의 기본 문단 모양으로 넣는다.
    static func trailingCodeLineStyle(level: Int, style: EditorStyle) -> NSParagraphStyle {
        let textStart = CGFloat(level) * style.indent + style.codeBlockPadX
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = textStart
        paragraph.headIndent = textStart
        paragraph.tailIndent = -style.codeBlockPadX
        paragraph.minimumLineHeight = style.codeBlock.lineHeight
        paragraph.maximumLineHeight = style.codeBlock.lineHeight
        return paragraph
    }

    private struct Builder {
        let out: NSMutableAttributedString
        let line: MarkdownLine
        let key: LineRenderKey
        let style: EditorStyle
        let scheduleInset: CGFloat
        let decoration: FragmentDecoration

        init(out: NSMutableAttributedString, line: MarkdownLine, key: LineRenderKey, style: EditorStyle, scheduleInset: CGFloat) {
            self.out = out
            self.line = line
            self.key = key
            self.scheduleInset = scheduleInset
            self.style = style
            self.decoration = FragmentDecoration(style: style)
        }

        private var full: NSRange { NSRange(location: 0, length: out.length) }

        /// 문서 기준 범위를 문단 안의 범위로.
        private func local(_ range: NSRange) -> NSRange {
            NSIntersectionRange(NSRange(location: range.location - line.start, length: range.length), full)
        }

        // MARK: 감추기, 기호

        private func hide(_ range: NSRange, kernAfter: CGFloat = 0) {
            let r = local(range)
            guard r.length > 0 else { return }
            out.addAttributes([.font: style.hidden, .foregroundColor: NSColor.clear], range: r)
            out.removeAttribute(.strikethroughStyle, range: r)
            out.removeAttribute(.underlineStyle, range: r)
            out.removeAttribute(.kern, range: r)
            out.removeAttribute(.baselineOffset, range: r)
            out.removeAttribute(.markdownLink, range: r)
            if kernAfter > 0 {
                out.addAttribute(.kern, value: kernAfter, range: NSRange(location: NSMaxRange(r) - 1, length: 1))
            }
        }

        /// 인라인 기호는 커서가 있는 줄에서도 보이지 않는다(D-036).
        private func marker(_ range: NSRange, kernAfter: CGFloat = 0) {
            hide(range, kernAfter: kernAfter)
        }

        /// 줄 앞의 감춘 탭이 자리를 차지하지 않도록 탭 자리를 글자 시작점 바로 뒤에 촘촘히 둔다.
        private func tabStops(after x: CGFloat) -> [NSTextTab] {
            (0..<line.indentLength).map {
                NSTextTab(textAlignment: .left, location: x + CGFloat($0 + 1) * EditorMetrics.hiddenFontSize)
            }
        }

        // MARK: 접힌 줄

        func collapse() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = EditorMetrics.collapsedLineHeight
            paragraph.maximumLineHeight = EditorMetrics.collapsedLineHeight
            paragraph.lineBreakMode = .byClipping
            paragraph.tabStops = []
            paragraph.defaultTabInterval = EditorMetrics.hiddenFontSize
            out.addAttributes([
                .font: style.hidden,
                .foregroundColor: NSColor.clear,
                .paragraphStyle: paragraph,
            ], range: full)
            decoration.isCollapsed = true
        }

        // MARK: 본문, 제목, 목록

        func styleText() {
            let font: EditorStyle.TextFont
            var tracking: CGFloat = 0
            var spacing: (before: CGFloat, after: CGFloat) = (0, 0)
            if let level = key.kind.headingLevel {
                font = style.heading(level)
                tracking = style.headingTracking[level - 1]
                spacing = style.metrics.headingSpacing[level - 1]
            } else {
                font = style.body
            }
            let isDone = key.kind == .todo(done: true)
            let isQuote = key.kind == .quote
            // 인용문의 글자는 `text-2`다. 서식(형광펜, 코드)의 글자색은 그 위에 입힌다.
            let baseColor = isDone ? style.text3 : isQuote ? style.text2 : style.text

            let left = CGFloat(key.level) * style.indent
            if case .toggleHeading = key.kind {
                decoration.chevronSize = font.font.pointSize * style.metrics.headingChevronScale
            }
            let textStart = left + (key.kind.isListItem ? decoration.gutterWidth : isQuote ? style.quotePadding : 0)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = font.lineHeight
            paragraph.maximumLineHeight = font.lineHeight
            paragraph.firstLineHeadIndent = textStart
            paragraph.headIndent = textStart
            paragraph.tailIndent = -scheduleInset
            paragraph.paragraphSpacingBefore = key.isContinuation ? 0 : spacing.before
            paragraph.paragraphSpacing = key.hasHardBreak ? 0 : spacing.after
            paragraph.tabStops = tabStops(after: textStart)

            var base: [NSAttributedString.Key: Any] = [
                .font: font.font,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraph,
            ]
            if tracking != 0 { base[.kern] = tracking }
            out.addAttributes(base, range: full)
            decoration.lineFont = font.font

            if isDone {
                out.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: style.text3,
                ], range: local(line.contentRange))
            }

            let isHeading = key.kind.headingLevel != nil
            for span in line.spans { apply(span, lineFont: font, isHeading: isHeading, isDone: isDone) }

            // 줄 머리(들여쓰기, 목록 기호, 제목의 `#`)는 늘 감춘다.
            hide(line.indentRange)
            hide(line.markerRange)

            if line.hasHardBreak { hide(NSRange(location: line.contentEnd, length: 1)) }
            guard !key.isContinuation else { return }
            decoration.gutterX = left
            switch key.kind {
            case .todo(let done): decoration.gutter = .checkbox(done: done)
            case .bullet: decoration.gutter = .bullet(key.level % 3)
            case .toggle, .toggleHeading: decoration.gutter = .chevron(open: !key.isFolded)
            case .quote: decoration.quoteBar = true
            default: break
            }
        }

        private func apply(_ span: InlineSpan, lineFont: EditorStyle.TextFont, isHeading: Bool, isDone: Bool) {
            let content = local(span.contentRange)
            switch span.kind {
            case .bold:
                if !isHeading { out.addAttribute(.font, value: style.strong, range: content) }
                marker(span.openMarker)
                marker(span.closeMarker)

            case .strike:
                var attributes: [NSAttributedString.Key: Any] = [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: isDone ? style.text3 : style.text2,
                ]
                if !isDone { attributes[.foregroundColor] = style.text2 }
                out.addAttributes(attributes, range: content)
                marker(span.openMarker)
                marker(span.closeMarker)

            case .highlight(let number):
                if !isDone { out.addAttribute(.foregroundColor, value: style.highlightForeground(number), range: content) }
                let color = style.highlightBackground(number)
                out.addAttribute(.markdownHighlight, value: InlineBackground(
                    kind: .highlight(number), color: isDone ? color.withAlphaComponent(color.alphaComponent * style.doneFade) : color,
                    padX: style.metrics.highlightPadX,
                    height: min(lineFont.lineHeight, lineFont.glyphHeight + style.metrics.highlightPadY * 2),
                    leadShift: style.metrics.highlightPadX / 2
                ), range: content)
                marker(span.openMarker, kernAfter: style.metrics.highlightPadX)
                marker(span.closeMarker, kernAfter: style.metrics.highlightPadX)

            case .code:
                // 글자는 줄 글꼴에 맞춘 고정폭, 상자는 높이를 정해 두고 글자 위아래가 같게 놓는다.
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: style.inlineCode(in: lineFont),
                    .baselineOffset: style.codeRise,
                ]
                if !isDone { attributes[.foregroundColor] = style.inlineCodeForeground }
                out.addAttributes(attributes, range: content)
                out.removeAttribute(.kern, range: content)
                let room = style.codePadX + style.codeGap
                out.addAttribute(.markdownCodeBox, value: InlineBackground(
                    kind: .code, color: style.codeBackground,
                    padX: style.codePadX,
                    height: style.codeHeight(in: lineFont),
                    drop: style.codeDrop,
                    leadShift: room / 2
                ), range: content)
                marker(span.openMarker, kernAfter: room)
                marker(span.closeMarker, kernAfter: room)

            case .link(let url):
                let isHovered = key.hoveredLink == span.range.location - line.start
                var attributes: [NSAttributedString.Key: Any] = [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: isHovered ? style.text : style.text3,
                    .markdownLink: url,
                ]
                if !isDone { attributes[.foregroundColor] = style.link }
                let string = out.string as NSString
                let letters = CharacterSet.whitespacesAndNewlines.inverted
                let first = string.rangeOfCharacter(from: letters, options: [], range: content)
                if first.location != NSNotFound {
                    let last = string.rangeOfCharacter(from: letters, options: .backwards, range: content)
                    out.addAttributes(attributes, range: NSUnionRange(first, last))
                }
                marker(span.openMarker)
                marker(span.closeMarker)

            case .escape:
                // 백슬래시만 감춘다. 막은 글자는 보통 글자다.
                marker(span.openMarker)
            }
        }

        // MARK: 코드 블록

        func styleCode() {
            let font = style.codeBlock
            let boxX = CGFloat(key.level) * style.indent
            let textStart = boxX + style.codeBlockPadX
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = textStart
            paragraph.headIndent = textStart
            paragraph.tailIndent = -(style.codeBlockPadX + scheduleInset)
            paragraph.tabStops = tabStops(after: textStart)
            paragraph.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: font.font]).width

            var lineHeight = font.lineHeight
            var color = style.codeForeground
            let isFence = key.kind != .code
            if isFence {
                // ``` 줄은 보이지 않고(언어 이름도), 상자의 위아래 안쪽 여백 높이만 차지한다(D-036).
                if key.kind == .fenceOpen, !key.isFirst { paragraph.paragraphSpacingBefore = style.codeBlockGap }
                if key.kind == .fenceClose { paragraph.paragraphSpacing = style.codeBlockGap }
                // 코드 줄이 없는 블록은 커서가 놓이는 ``` 줄을 빈 코드 줄의 높이로 둔다.
                lineHeight = key.isEmptyBlockSpot ? font.lineHeight : style.codeBlockPadY
                paragraph.lineBreakMode = .byClipping
            } else if isComment(out.string) {
                color = style.comment
            }
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight

            out.addAttributes([
                .font: font.font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ], range: full)
            decoration.lineFont = font.font
            hide(line.indentRange)
            if isFence { hide(line.range) }

            decoration.codeBox = (key.isCodeTop, key.isCodeBottom || key.hasTrailingCodeLine)
            decoration.codeBoxCoversExtraLine = key.hasTrailingCodeLine
            decoration.codeBoxX = boxX
        }

        /// 주석 줄(`//`, `#`으로 시작)은 흐리게 한다. 구문 색은 없다.
        private func isComment(_ text: String) -> Bool {
            let trimmed = text.drop { $0 == " " || $0 == "\t" }
            return trimmed.hasPrefix("//") || trimmed.hasPrefix("#")
        }
    }
}
