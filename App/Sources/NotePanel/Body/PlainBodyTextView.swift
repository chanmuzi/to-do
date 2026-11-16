import AppKit
import Theme

/// 기본 편집기의 텍스트 뷰. 위아래 여백이 다른 `doc-pad`를 맞춘다.
/// 입력 커서는 시스템의 것을 그대로 쓴다(옛 그리기 경로를 덮어쓰면 자국이 남는다, D-025).
final class PlainBodyTextView: NSTextView {
    var padding: ThemeInsets? {
        didSet {
            guard let padding else { return }
            // 텍스트 뷰는 위아래에 같은 여백만 받는다. 합을 반씩 주고 시작점을 위쪽 여백으로 옮긴다.
            textContainerInset = NSSize(width: padding.leading, height: (padding.top + padding.bottom) / 2)
            invalidateTextContainerOrigin()
        }
    }

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
}
