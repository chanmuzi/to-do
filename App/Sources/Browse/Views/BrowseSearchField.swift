import AppKit
import Theme

final class BrowseSearchField: NSView {
    static let placeholder = "노트 찾기"
    private let style: BrowseStyle
    private let icon = NSImageView()
    let input: CommandInputField
    let textView: BrowseTextView

    init(style: BrowseStyle) {
        self.style = style
        textView = BrowseTextView(theme: style.theme)
        input = CommandInputField(theme: style.theme, editor: textView)
        super.init(frame: .zero)
        icon.imageScaling = .scaleNone
        icon.setAccessibilityElement(false)
        input.setAccessibilityLabel(Self.placeholder)
        [icon, input].forEach(addSubview)
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

    var isPlaceholderVisible: Bool { textView.string.isEmpty }

    func refreshTheme() {
        icon.image = style.symbol("magnifyingglass", size: .iconSmall)
        icon.contentTintColor = style.color(.text3)
        input.apply(font: style.plainFont, ink: style.color(.text), placeholder: Self.placeholder,
                    placeholderInk: style.color(.text4))
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(input) }

    override func layout() {
        super.layout()
        let side = style.leadWidth
        let slot = NSRect(x: style.rowPadding, y: (bounds.height - side) / 2, width: side, height: side)
        icon.frame = style.theme.symbolFrame(slot)
        let x = slot.maxX + style.theme.space(.sp2) - BrowseStyle.labelInset
        let h = ceil(input.intrinsicContentSize.height)
        input.frame = NSRect(x: x, y: ((bounds.height - h) / 2).rounded(), width: max(0, bounds.width - x), height: h)
    }
}
