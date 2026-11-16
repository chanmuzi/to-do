import AppKit
import Theme

/// 동작 한 줄: "“검색어” 새 노트 만들기"(`text-2`)와 "라이브러리 열기". 앞에 14pt 아이콘(`text-2`).
final class BrowseActionRowView: BrowseEntryView {
    private let symbolName: String
    private let textColor: ColorToken
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(style: BrowseStyle, symbolName: String, title: String, textColor: ColorToken) {
        self.symbolName = symbolName
        self.textColor = textColor
        super.init(style: style)
        label.stringValue = title
        label.lineBreakMode = .byTruncatingMiddle
        iconView.imageScaling = .scaleProportionallyDown
        for view in [iconView, label] {
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        refreshTheme()
    }

    var title: String { label.stringValue }

    override func refreshTheme() {
        iconView.image = style.symbol(symbolName, size: .iconLarge)
        iconView.contentTintColor = style.color(.text2)
        label.font = style.plainFont
        label.textColor = style.color(textColor)
        super.refreshTheme()
    }

    override func layout() {
        super.layout()
        let lead = style.leadWidth
        iconView.frame = centered(width: lead, height: lead, x: style.rowPadding)
        let labelX = iconView.frame.maxX + style.theme.component(.browseGap)
        label.frame = style.labelFrame(
            label, textX: labelX, textWidth: bounds.width - style.rowPadding - labelX, centeredIn: bounds.height
        )
    }
}

/// 구획 이름("떠 있는 노트", "최근에 연 노트"): 11pt `text-3`.
final class BrowseHeaderView: BrowseEntryView {
    private let label = NSTextField(labelWithString: "")

    init(style: BrowseStyle, title: String) {
        super.init(style: style)
        label.stringValue = title
        addSubview(label)
        refreshTheme()
    }

    var title: String { label.stringValue }

    override var height: CGFloat { style.headerHeight }

    override func refreshTheme() {
        label.font = style.headerFont
        label.textColor = style.color(.text3)
        super.refreshTheme()
    }

    override func layout() {
        super.layout()
        let theme = style.theme
        let size = style.fittingSize(of: label)
        let lineHeight = theme.lineHeight(.micro)
        label.frame = NSRect(
            x: style.rowPadding - BrowseStyle.labelInset,
            y: theme.space(.sp2) + ((lineHeight - size.height) / 2).rounded(),
            width: max(0, bounds.width - style.rowPadding * 2) + BrowseStyle.labelInset * 2, height: size.height
        )
    }
}

/// "라이브러리 열기" 위의 구분선(`line`).
final class BrowseSeparatorView: BrowseEntryView {
    private let lineView = NSView()

    override init(style: BrowseStyle) {
        super.init(style: style)
        lineView.wantsLayer = true
        addSubview(lineView)
    }

    override var height: CGFloat { style.separatorHeight }

    override func updateLayer() {
        super.updateLayer()
        lineView.layer?.backgroundColor = style.cgColor(.line, in: self)
    }

    override func layout() {
        super.layout()
        let thickness = style.theme.shape(.borderWidth)
        lineView.frame = NSRect(
            x: style.rowPadding, y: ((bounds.height - thickness) / 2).rounded(.down),
            width: max(0, bounds.width - style.rowPadding * 2), height: thickness
        )
    }
}
