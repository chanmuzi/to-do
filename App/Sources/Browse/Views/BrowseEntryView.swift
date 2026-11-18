import AppKit
import Theme

/// 목록에 놓이는 뷰의 바탕. 고를 수 있는 줄은 고르거나 마우스를 올리면 `selected` 바탕이 줄 전체에 겹친다
/// (색을 입힌 줄 위에도, spec 14). 그 위에서도 마우스는 화살표다(규칙 9).
class BrowseEntryView: NSView {
    let style: BrowseStyle
    private let highlightView = NSView()
    private(set) var isHighlighted = false

    init(style: BrowseStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        highlightView.wantsLayer = true
        highlightView.alphaValue = 0
        highlightView.autoresizingMask = [.width, .height]
        addSubview(highlightView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 줄의 높이.
    var height: CGFloat { style.theme.component(.browseRowHeight) }

    /// `selected` 바탕을 `dur` 동안 겹치거나 걷는다(규칙 8).
    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        let alpha: CGFloat = highlighted ? 1 : 0
        guard animated else {
            highlightView.alphaValue = alpha
            return
        }
        style.animate { highlightView.animator().alphaValue = alpha }
    }

    func refreshTheme() {
        needsDisplay = true
        needsLayout = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let radius = style.theme.component(.browseRowRadius)
        layer?.cornerRadius = radius
        highlightView.layer?.cornerRadius = radius
        highlightView.layer?.backgroundColor = style.cgColor(.menuHighlight, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// 세로 가운데에 놓은 틀.
    func centered(width: CGFloat, height: CGFloat, x: CGFloat) -> NSRect {
        NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
    }
}
