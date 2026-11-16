import AppKit
import Theme

/// 오른쪽 아래의 휴지통과 닫기(spec 5.3). 본문 위에 겹쳐 뜨고 본문 크기에 영향을 주지 않는다.
final class CornerButtonsView: NSView {
    let trashButton: IconButton
    let closeButton: IconButton
    private let style: PanelStyle

    init(style: PanelStyle) {
        self.style = style
        trashButton = IconButton(style: style, symbolName: "trash", iconSize: .iconLarge, label: "휴지통으로 보내기")
        closeButton = IconButton(style: style, symbolName: "xmark", iconSize: .iconMedium, label: "창 닫기")
        super.init(frame: .zero)
        // 알파 전환을 레이어가 맡는다(호버로 나타나고 사라짐).
        wantsLayer = true
        [trashButton, closeButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    var preferredSize: NSSize {
        let button = style.theme.component(.iconButton)
        return NSSize(width: button * 2 + style.theme.component(.iconButtonGap), height: button)
    }

    func refreshTheme() {
        [trashButton, closeButton].forEach { $0.refresh() }
        needsLayout = true
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let button = style.theme.component(.iconButton)
        trashButton.frame = NSRect(x: 0, y: 0, width: button, height: button)
        closeButton.frame = NSRect(
            x: button + style.theme.component(.iconButtonGap), y: 0, width: button, height: button
        )
    }

    /// 버튼 사이의 틈은 본문이 받는다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
