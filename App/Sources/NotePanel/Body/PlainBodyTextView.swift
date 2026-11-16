import AppKit
import Theme

/// 기본 편집기의 텍스트 뷰. 위아래 여백이 다른 `doc-pad`와 얇은 커서(규칙 15)를 맞춘다.
final class PlainBodyTextView: NSTextView {
    var padding: ThemeInsets? {
        didSet {
            guard let padding else { return }
            // 텍스트 뷰는 위아래에 같은 여백만 받는다. 합을 반씩 주고 시작점을 위쪽 여백으로 옮긴다.
            textContainerInset = NSSize(width: padding.leading, height: (padding.top + padding.bottom) / 2)
            invalidateTextContainerOrigin()
        }
    }

    var caretWidth: CGFloat = 0
    /// 너비가 바뀌면 줄바꿈이 달라져 내용 높이도 달라진다.
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    override var textContainerOrigin: NSPoint {
        guard let padding else { return super.textContainerOrigin }
        return NSPoint(x: padding.leading, y: padding.top)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        if caretWidth > 0 { caret.size.width = caretWidth }
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }
}
