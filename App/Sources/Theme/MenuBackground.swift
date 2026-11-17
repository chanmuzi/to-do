import AppKit

public extension NSView {
    /// 이 뷰가 든 메뉴의 바탕 전체를 `color`로 채운다.
    ///
    /// 시스템 메뉴는 첫 줄 위와 마지막 줄 아래에 여백을 두고, 그 여백은 반투명 재질이라 메뉴 뒤가 비친다.
    /// 줄만 불투명하게 칠하면 뒤가 어두울 때 위아래에 어두운 띠가 보인다. 메뉴의 줄들을 담은 문서 뷰
    /// (`NSClipView` 바로 아래)를 같은 색으로 칠해 여백까지 줄과 같은 바탕으로 만든다.
    /// 메뉴 창에 들어 있지 않으면 아무것도 하지 않는다. 모서리는 메뉴 창이 둥글게 자른다.
    func fillEnclosingMenuBackground(with color: CGColor) {
        guard window != nil else { return }
        var candidate: NSView? = superview
        while let view = candidate, !(view.superview is NSClipView) {
            candidate = view.superview
        }
        guard let documentView = candidate else { return }
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = color
    }
}
