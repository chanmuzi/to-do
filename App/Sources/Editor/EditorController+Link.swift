import AppKit
import Theme

// 링크의 주소는 화면에 보이지 않는다(`[글자](주소)`에서 글자만 보인다). 주소를 적고 고치는 일은
// 고른 글자 아래에 뜨는 작은 칸에서 한다.

extension EditorController {
    /// 링크 단축키. 글자를 골랐으면 주소를 물어 링크로 만들고, 커서가 링크 안이면 그 주소를 고친다
    /// (주소를 비우면 링크를 벗긴다).
    func beginLinkEditing() {
        guard linkSession == nil, !textView.hasMarkedText(), textView.isEditable,
              let target = EditorCommands.linkTarget(document, selection: clamped(textView.selectedRange())) else { return }
        linkSession = (target, documentVersion)
        linkField.address = EditorCommands.linkAddress(document, for: target)
        linkField.isHidden = false
        layoutLinkField()
        textView.window?.makeFirstResponder(linkField.input)
        reportContentHeight()
    }

    /// 주소 칸에서 Return. 그사이에 원문이 바뀌었으면(다른 프로그램이 고침) 넣지 않는다.
    func commitLink(_ address: String) {
        guard let session = linkSession else { return }
        endLinkEditing()
        guard session.version == documentVersion else { return }
        apply(EditorCommands.setLink(document, target: session.target, address: address))
    }

    func cancelLinkEditing() {
        guard linkSession != nil else { return }
        endLinkEditing()
    }

    private func endLinkEditing() {
        linkSession = nil
        linkField.isHidden = true
        if let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
        reportContentHeight()
    }

    /// 주소 칸을 대상 글자의 마지막 줄 아래에, 본문 너비 안에 놓는다.
    func layoutLinkField() {
        guard let session = linkSession else { return }
        let range: NSRange
        switch session.target {
        case .existing(let span): range = span.contentRange
        case .new(let selected): range = selected
        }
        let origin = textView.textContainerOrigin
        let anchor = segmentRects(for: clamped(range)).last
            ?? CGRect(x: origin.x, y: origin.y, width: 0, height: style.body.lineHeight)
        let width = min(theme.component(.linkFieldWidth), textContainer.size.width)
        let x = min(max(anchor.minX, origin.x), origin.x + textContainer.size.width - width)
        linkField.frame = CGRect(
            x: x.rounded(),
            y: (anchor.maxY + style.metrics.linkFieldGap).rounded(),
            width: width,
            height: theme.component(.controlHeight)
        )
    }

    /// 그 범위의 글자가 차지하는 사각형들(화면 줄마다 하나). 텍스트 뷰 좌표.
    func segmentRects(for range: NSRange) -> [CGRect] {
        let base = contentStorage.documentRange.location
        guard let start = contentStorage.location(base, offsetBy: range.location),
              let end = contentStorage.location(base, offsetBy: NSMaxRange(range)),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        layoutManager.ensureLayout(for: textRange)
        let origin = textView.textContainerOrigin
        var rects: [CGRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return rects
    }
}
