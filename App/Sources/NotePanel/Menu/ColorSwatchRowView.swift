import AppKit
import Theme

/// 더 보기 메뉴의 노트 색 줄(spec 5.4): 물방울 아이콘 뒤에 색 칸 아홉 개(없음 + 팔레트 여덟)가 한 줄로 놓인다.
final class ColorSwatchRowView: NSView {
    private let style: PanelStyle
    private let iconView = NSImageView()
    private let swatches: [SwatchView]

    /// - Parameter onSelect: 고른 팔레트 키. 색 없음이면 `nil`.
    init(style: PanelStyle, selectedPaletteID: String?, onSelect: @escaping (String?) -> Void) {
        self.style = style
        let theme = style.theme
        let entries: [PaletteColor?] = [nil] + theme.palette.map { Optional($0) }
        swatches = entries.map { SwatchView(style: style, palette: $0, isSelected: $0?.id == selectedPaletteID) }
        super.init(frame: NSRect(
            x: 0, y: 0, width: theme.component(.menuWidth), height: theme.component(.rowHeight)
        ))
        wantsLayer = true
        autoresizingMask = [.width]
        iconView.image = style.symbol("drop", size: .menuIcon)
        iconView.contentTintColor = style.color(.text2)
        iconView.imageScaling = .scaleNone
        iconView.setAccessibilityLabel("노트 색")
        addSubview(iconView)
        for (swatch, entry) in zip(swatches, entries) {
            swatch.onSelect = { [unowned self] in
                enclosingMenuItem?.menu?.cancelTracking()
                onSelect(entry?.id)
            }
            addSubview(swatch)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    /// 다른 줄처럼 불투명한 `surface` 바탕(`MenuRowView`).
    override func updateLayer() {
        layer?.backgroundColor = style.cgColor(.surface, in: self)
    }

    override func layout() {
        super.layout()
        let theme = style.theme
        let icon = theme.component(.iconLarge)
        let size = theme.component(.swatchSize)
        let contentX = theme.space(.sp1) + theme.space(.sp2)
        iconView.frame = style.theme.symbolFrame(
            NSRect(x: contentX, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
        )
        let firstX = contentX + icon + theme.space(.sp2)
        let outset = SwatchView.outset(style)
        for (index, swatch) in swatches.enumerated() {
            swatch.frame = NSRect(
                x: firstX + CGFloat(index) * (size + theme.component(.swatchGap)),
                y: (bounds.height - size) / 2, width: size, height: size
            ).insetBy(dx: -outset, dy: -outset)
        }
    }
}
