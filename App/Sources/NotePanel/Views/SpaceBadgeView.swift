import AppKit
import Theme
import SpaceIcons

/// 상단 줄 맨 앞의 스페이스 표시: 아이콘, 아이콘과 이름, 이름(spec 5.2).
final class SpaceBadgeView: NSView {
    private let style: PanelStyle
    private let iconView = SpaceIconNSView(frame: .zero)
    private let nameLabel = NSTextField(labelWithString: "")
    private var badge: TopRowState.SpaceBadge?
    private var colorToken: ColorToken = .text3

    init(style: PanelStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        nameLabel.lineBreakMode = .byTruncatingTail
        [iconView, nameLabel].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    func apply(_ badge: TopRowState.SpaceBadge?, color: ColorToken, animated: Bool) {
        if color != colorToken && animated { style.crossfade(self) }
        self.badge = badge
        colorToken = color
        refresh()
    }

    func refresh() {
        isHidden = badge == nil
        iconView.isHidden = badge?.icon == nil || badge?.icon == .some(.none)
        if let badge, let directory = badge.imageDirectory {
            iconView.apply(badge.icon, directory: directory, theme: style.theme,
                           size: style.theme.component(.iconMedium), color: style.color(colorToken), symbolSize: .iconMedium)
        }
        nameLabel.stringValue = badge?.name ?? ""
        nameLabel.font = style.theme.nsFont(.title, weight: style.theme.tokens.textStyle(.body).weight)
        nameLabel.textColor = style.color(colorToken)
        nameLabel.isHidden = badge?.name == nil
        setAccessibilityLabel(badge?.name ?? "스페이스")
        needsLayout = true
    }

    private var iconWidth: CGFloat {
        if !iconView.isHidden { return style.theme.component(.iconMedium) }
        return 0
    }

    private var nameWidth: CGFloat {
        nameLabel.isHidden ? 0 : nameLabel.intrinsicContentSize.width.rounded(.up)
    }

    /// 자리 너비. 스페이스가 없으면 `nil`(자리 자체가 없다).
    var fittingWidth: CGFloat? {
        guard badge != nil else { return nil }
        let gap = iconWidth > 0 && nameWidth > 0 ? style.theme.space(.sp1) : 0
        return iconWidth + gap + nameWidth
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        func centered(_ width: CGFloat, _ height: CGFloat, x: CGFloat) -> NSRect {
            NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
        }
        let icon = style.theme.component(.iconMedium)
        iconView.frame = centered(icon, icon, x: 0)
        let nameX = iconWidth > 0 ? iconWidth + style.theme.space(.sp1) : 0
        nameLabel.frame = centered(
            max(0, bounds.width - nameX), nameLabel.intrinsicContentSize.height.rounded(.up), x: nameX
        )
    }
}
