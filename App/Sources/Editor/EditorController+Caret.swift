import AppKit
import Theme

// 입력 커서는 편집기가 직접 놓는다(`Theme.TextCaret`). 시스템의 커서 표시는 줄 높이 전체를 덮고 너비를
// 정할 수 없어 쓰지 않는다(`EditorTextView.shouldDrawInsertionPoint`). 여기서는 커서가 놓일 자리만 잰다:
// 가로는 TextKit 2가 놓은 줄 조각에서의 글자 경계, 세로는 그 자리 글꼴의 ascender부터 descender까지다.

extension EditorController {
    /// 커서 자리의 글꼴 상자(텍스트 뷰 좌표). 선택이 있거나 놓을 자리가 없으면 `nil`.
    func caretRect() -> NSRect? {
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location <= document.length else { return nil }
        let location = selection.location
        let index = document.lineIndex(at: location)
        let line = document.lines[index]
        guard let spot = caretSpot(location, lineIndex: index) else { return nil }
        let lineFont = self.lineFont(for: line, at: index)
        let caret = caretFont(for: line, at: location, lineFont: lineFont)
        // 글자는 줄 높이의 세로 가운데에 그린다(`MarkdownLayoutFragment.textShift`). 그 기준선에 맞춘다.
        let baseline = spot.line.midY + (lineFont.font.ascender + lineFont.font.descender) / 2
        let top = baseline - caret.rise - caret.font.ascender
        let height = TextCaret.glyphBoxHeight(of: caret.font)
        let origin = textView.textContainerOrigin
        return NSRect(x: origin.x + spot.x + caret.shift, y: origin.y + top, width: 0, height: height)
    }

    /// 그 줄의 기본 글꼴.
    private func lineFont(for line: MarkdownLine, at index: Int) -> EditorStyle.TextFont {
        switch line.kind {
        case .heading(let level): style.heading(level)
        case .fenceOpen, .fenceClose, .code: style.codeBlock
        default: style.body
        }
    }

    /// 커서 자리에서 칠 글자의 글꼴. 인라인 코드 안에서는 코드 글꼴이고 그만큼 올려 그린다.
    /// `shift`: 감춘 여는 기호 뒤에 준 자간은 글자 위치에 절반만 잡힌다. 구간의 맨 앞(기호 안쪽)에서 그만큼 민다.
    private func caretFont(
        for line: MarkdownLine, at location: Int, lineFont: EditorStyle.TextFont
    ) -> (font: NSFont, rise: CGFloat, shift: CGFloat) {
        guard !line.kind.isCode else { return (lineFont.font, 0, 0) }
        for span in line.spans where NSLocationInRange(location, span.contentRange) || location == NSMaxRange(span.contentRange) {
            let atStart = location == span.contentRange.location
            switch span.kind {
            case .code:
                return (style.inlineCode(in: lineFont), style.codeRise, atStart ? (style.codePadX + style.codeGap) / 2 : 0)
            case .highlight:
                if atStart { return (lineFont.font, 0, style.metrics.highlightPadX / 2) }
            default:
                continue
            }
        }
        return (lineFont.font, 0, 0)
    }

    /// 커서가 놓이는 줄 조각의 영역과 그 안의 가로 자리(텍스트 컨테이너 좌표).
    private func caretSpot(_ location: Int, lineIndex index: Int) -> (x: CGFloat, line: CGRect)? {
        let line = document.lines[index]
        let base = contentStorage.documentRange.location
        if line.fullRange.length > 0,
           let start = contentStorage.location(base, offsetBy: line.start),
           let fragment = layoutManager.textLayoutFragment(for: start) {
            layoutManager.ensureLayout(for: fragment.rangeInElement)
            let offset = location - line.start
            let lines = fragment.textLineFragments.filter { $0.characterRange.length > 0 }
            // 줄이 넘어간 경계에서는 커서가 온 쪽을 따른다(End로 왔으면 윗줄의 끝, 그 밖에는 아랫줄의 앞).
            let upstream = textView.selectionAffinity == .upstream
            let found = lines.firstIndex { fragmentLine in
                let range = fragmentLine.characterRange
                return offset >= range.location && (offset < NSMaxRange(range) || (upstream && offset == NSMaxRange(range)))
            }
            if let chosen = found.map({ lines[$0] }) ?? lines.last {
                let bounds = chosen.typographicBounds
                let frame = fragment.layoutFragmentFrame
                return (
                    frame.minX + bounds.minX + chosen.locationForCharacter(at: offset).x,
                    bounds.offsetBy(dx: frame.minX, dy: frame.minY)
                )
            }
        }
        // 글자가 없는 줄(문서 끝의 빈 줄, 빈 문서)은 문단이 없다. TextKit이 주는 커서 구간을 쓴다.
        guard let textLocation = contentStorage.location(base, offsetBy: location) else { return nil }
        var found: CGRect?
        layoutManager.enumerateTextSegments(
            in: NSTextRange(location: textLocation), type: .standard, options: [.rangeNotRequired]
        ) { _, frame, _, _ in
            found = frame
            return false
        }
        return found.map { ($0.minX, $0) }
    }
}
