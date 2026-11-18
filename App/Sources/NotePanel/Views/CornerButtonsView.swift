import AppKit
import Theme

final class CornerButtonsView: NSView {
    let trashButton: IconButton
    private let style: PanelStyle
    private let divider = NSView()
    private let rule = NSView()
    private var buttons: [(NoteFormat, IconButton)] = []
    var onFormat: ((NoteFormat) -> Void)?
    private(set) var showsFormats = false

    init(style: PanelStyle) {
        self.style = style
        trashButton = IconButton(style: style, symbolName: "trash", iconSize: .iconMedium, label: "휴지통으로 보내기")
        super.init(frame: .zero)
        wantsLayer = true
        let items: [(NoteFormat, String, String)] = [
            (.bold, "bold", "굵게"), (.strike, "strikethrough", "취소선"), (.highlight, "highlighter", "형광펜"),
            (.code, "chevron.left.forwardslash.chevron.right", "인라인 코드"), (.link, "link", "링크"),
            (.checklist, "checklist", "체크 목록"), (.bullet, "list.bullet", "글머리 목록")
        ]
        for (format, symbol, label) in items {
            let button = IconButton(style: style, symbolName: symbol, iconSize: .iconMedium, label: label)
            button.onPress = { [weak self] in self?.onFormat?(format) }
            buttons.append((format, button))
            addSubview(button)
        }
        [rule, divider, trashButton].forEach(addSubview)
        rule.wantsLayer = true
        divider.wantsLayer = true
        apply(visible: false, active: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

    func apply(visible: Bool, active: Set<NoteFormat>) {
        showsFormats = visible
        for (format, button) in buttons {
            button.isHidden = !visible
            button.isSelected = active.contains(format)
        }
        divider.isHidden = !visible
        rule.isHidden = !visible
        needsLayout = true
        needsDisplay = true
    }

    func refreshTheme() {
        buttons.forEach { $0.1.refresh() }
        trashButton.refresh()
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = showsFormats ? style.cgColor(.surface, in: self) : CGColor.clear
        divider.layer?.backgroundColor = style.cgColor(.line, in: self)
        rule.layer?.backgroundColor = style.cgColor(.connectFill, in: self)
    }

    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let theme = style.theme, side = theme.component(.iconButton)
        let pad = theme.component(.chromePaddingEnd), gap = theme.component(.iconButtonGap)
        let y = (bounds.height - side) / 2
        trashButton.frame = CGRect(x: bounds.width - pad - side, y: y, width: side, height: side)
        var x = pad
        for (format, button) in buttons {
            if format == .checklist {
                x += theme.component(.iconGap)
                let h = theme.component(.iconMedium)
                divider.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: theme.shape(.borderWidth), height: h)
                x = divider.frame.maxX + theme.component(.iconGap) + gap
            }
            button.frame = CGRect(x: x, y: y, width: side, height: side)
            x += side + gap
        }
        rule.frame = CGRect(x: 0, y: 0, width: bounds.width, height: theme.shape(.borderWidth))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self && !showsFormats ? nil : hit
    }
}
