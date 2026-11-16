import AppKit
import Theme

/// 메뉴 막대 메뉴의 한 줄(spec 4.3, 화면 8): 높이 `row-h`, 왼쪽에 14pt 아이콘, 고르는 중이면 `hover` 바탕.
/// 노트의 더 보기 메뉴와 같은 모양이다. 단축키는 적지 않는다(규칙 4).
final class MenuBarRowView: NSView {
    private let theme: Theme
    private let highlightView = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isShowingHighlight = false

    /// - Parameter isEnabled: 거짓이면 고를 수 없는 줄이다. 글자와 아이콘이 `text-3`이고 `hover` 바탕이 깔리지 않는다.
    init(theme: Theme, title: String, symbolName: String?, isEnabled: Bool = true) {
        self.theme = theme
        super.init(frame: NSRect(
            x: 0, y: 0, width: theme.component(.menuWidth), height: theme.component(.rowHeight)
        ))
        wantsLayer = true
        autoresizingMask = [.width]
        highlightView.wantsLayer = true
        iconView.image = symbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: theme.component(.iconLarge), weight: .regular)
            )
        }
        iconView.contentTintColor = theme.nsColor(isEnabled ? .text2 : .text3)
        iconView.imageScaling = .scaleProportionallyDown
        label.stringValue = title
        label.font = theme.nsFont(.body, size: theme.tokens.textStyle(.title).size)
        label.textColor = theme.nsColor(isEnabled ? .text : .text3)
        label.lineBreakMode = .byTruncatingTail
        [highlightView, iconView, label].forEach(addSubview)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let edge = theme.space(.sp1)
        let icon = theme.component(.iconLarge)
        func centered(x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
            NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
        }
        highlightView.frame = bounds.insetBy(dx: edge, dy: 0)
        let contentX = edge + theme.space(.sp2)
        iconView.frame = centered(x: contentX, width: icon, height: icon)
        // 아이콘이 없는 줄(종료)도 글자는 같은 자리에서 시작한다.
        let labelX = contentX + icon + theme.space(.sp2)
        label.frame = centered(
            x: labelX, width: max(0, bounds.width - contentX - labelX),
            height: label.intrinsicContentSize.height.rounded(.up)
        )
    }

    /// 메뉴가 고른 줄을 바꾸면 다시 그리라는 요청이 온다. 그때 바탕을 `dur` 동안 바꾼다(규칙 8).
    override func updateLayer() {
        highlightView.layer?.cornerRadius = theme.shape(.chipRadius)
        let highlighted = enclosingMenuItem.map { $0.isHighlighted && $0.isEnabled } == true
        guard highlighted != isShowingHighlight else { return }
        isShowingHighlight = highlighted
        var hover = CGColor.clear
        effectiveAppearance.performAsCurrentDrawingAppearance { hover = theme.nsColor(.hover).cgColor }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : theme.motion.duration
            context.timingFunction = theme.motion.timingFunction
            context.allowsImplicitAnimation = true
            highlightView.layer?.backgroundColor = highlighted ? hover : CGColor.clear
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}
