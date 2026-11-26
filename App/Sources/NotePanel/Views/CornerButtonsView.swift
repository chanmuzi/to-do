import AppKit
import Theme

final class CornerButtonsView: NSView {
    private let style: PanelStyle
    private let divider = NSView()
    private let rule = NSView()
    private let inkArrow: IconButton
    private let inkStrip = NSView()
    var inkMenu: (() -> NSMenu?)?
    var inkToken: ColorToken = .inkYellowBG
    private var buttons: [(NoteFormat, IconButton)] = []
    var onFormat: ((NoteFormat) -> Void)?
    private(set) var showsFormats = false

    init(style: PanelStyle) {
        self.style = style
        inkArrow = IconButton(style: style, symbolName: "chevron.down", iconSize: .iconSmall, label: "색 고르기")
        super.init(frame: .zero)
        inkArrow.onPress = { [weak self] in
            guard let self else { return }
            inkMenu?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: inkArrow.bounds.maxY), in: inkArrow)
        }
        inkStrip.wantsLayer = true
        wantsLayer = true
        let items: [(NoteFormat, String, String)] = [
            (.bold, "bold", "굵게"), (.strike, "strikethrough", "취소선"), (.highlight, "a", "마지막 색 걸기 또는 벗기기"),
            (.code, "chevron.left.forwardslash.chevron.right", "인라인 코드"), (.link, "link", "링크"),
            (.checklist, "checklist", "체크 목록"), (.bullet, "list.bullet", "글머리 목록")
        ]
        for (format, symbol, label) in items {
            let button = IconButton(style: style, symbolName: symbol, iconSize: .iconMedium, label: label)
            button.onPress = { [weak self] in self?.onFormat?(format) }
            if format == .highlight { button.addSubview(inkStrip) }
            buttons.append((format, button))
            addSubview(button)
        }
        [rule, divider, inkArrow].forEach(addSubview)
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
        inkArrow.isHidden = !visible
        divider.isHidden = !visible
        rule.isHidden = !visible
        needsLayout = true
        needsDisplay = true
    }

    func refreshTheme() {
        buttons.forEach { $0.1.refresh() }
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = showsFormats ? style.cgColor(.surface, in: self) : CGColor.clear
        inkStrip.layer?.backgroundColor = style.cgColor(inkToken, in: self)
        divider.layer?.backgroundColor = style.cgColor(.line, in: self)
        rule.layer?.backgroundColor = style.cgColor(.connectFill, in: self)
    }

    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let theme = style.theme, side = theme.component(.iconButton)
        let pad = theme.component(.chromePaddingEnd), gap = theme.component(.iconButtonGap)
        let y = (bounds.height - side) / 2
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
            if format == .highlight {
                let width = theme.component(.iconMedium)
                let thickness = theme.component(.swatchRing)
                inkStrip.frame = CGRect(x: (side - width) / 2, y: (side + width) / 2 - thickness,
                                        width: width, height: thickness)
                let arrowWidth = theme.component(.iconSmall)
                inkArrow.frame = CGRect(x: x - gap, y: y, width: arrowWidth, height: side)
                x += arrowWidth
            }
        }
        rule.frame = CGRect(x: 0, y: 0, width: bounds.width, height: theme.shape(.borderWidth))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self && !showsFormats ? nil : hit
    }
}
