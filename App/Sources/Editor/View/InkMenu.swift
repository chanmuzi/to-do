import AppKit
import MarkdownSyntax
import Theme

extension EditorController {
    func inkMenu() -> NSMenu {
        let menu = NSMenu(title: "색")
        let selected = selectedInk
        for foreground in [true, false] {
            let row = NSStackView()
            let size = theme.component(.swatchSize)
            let gap = theme.component(.swatchGap)
            let edge = theme.space(.sp2)
            let ring = theme.component(.swatchRing)
            row.spacing = gap - ring * 2
            row.edgeInsets = NSEdgeInsets(top: ring, left: edge, bottom: ring, right: edge)
            let label = NSTextField(labelWithString: foreground ? "A" : "▮")
            label.font = theme.nsFont(.micro)
            label.textColor = theme.nsColor(.text2)
            row.addArrangedSubview(label)
            let choices: [InkColor?] = [nil] + InkHue.palette.map { InkColor($0, foreground: foreground) }
            for choice in choices {
                let button = InkSwatch(theme: theme, color: choice, foreground: foreground, selected: selected == choice)
                button.choose = { [weak self, weak menu] in
                    menu?.supermenu?.cancelTracking()
                    menu?.cancelTracking()
                    self?.setInk(choice)
                }
                row.addArrangedSubview(button)
                let side = size + ring * 2
                NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: side),
                                             button.heightAnchor.constraint(equalToConstant: side)])
            }
            row.setFrameSize(NSSize(width: row.fittingSize.width, height: theme.component(.rowHeight)))
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        return menu
    }
}

private final class InkSwatch: NSButton {
    let theme: Theme
    let color: InkColor?
    let foreground: Bool
    let selected: Bool
    var choose: (() -> Void)?

    init(theme: Theme, color: InkColor?, foreground: Bool, selected: Bool) {
        self.theme = theme
        self.color = color
        self.foreground = foreground
        self.selected = selected
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(pick)
        let label = color?.label ?? (foreground ? "글자색 없음" : "바탕색 없음")
        toolTip = label
        setAccessibilityLabel(label)
        setAccessibilityValue(selected ? "고름" : nil)
    }

    required init?(coder: NSCoder) { fatalError("코드로만 만든다") }
    @objc private func pick() { choose?() }

    override func draw(_ dirtyRect: NSRect) {
        let ring = theme.component(.swatchRing)
        let radius = theme.shape(.checkRadius)
        let rect = bounds.insetBy(dx: ring, dy: ring)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if !foreground || color == nil {
            theme.nsColor(foreground ? .surface : color?.token ?? .surface).setFill()
            path.fill()
            theme.nsColor(.outline).setStroke()
            path.lineWidth = theme.shape(.borderWidth)
            path.stroke()
        }
        if foreground {
            let glyph = NSAttributedString(string: "A", attributes: [
                .font: theme.nsFont(.sectionLabel), .foregroundColor: theme.nsColor(color?.token ?? .text)
            ])
            let size = glyph.size()
            glyph.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
        if selected {
            let outer = bounds.insetBy(dx: ring / 2, dy: ring / 2)
            let path = NSBezierPath(roundedRect: outer, xRadius: radius + ring, yRadius: radius + ring)
            theme.nsColor(.text).setStroke()
            path.lineWidth = ring
            path.stroke()
        }
    }
}
