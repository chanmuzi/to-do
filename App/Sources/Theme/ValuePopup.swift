import AppKit
import SwiftUI

/// 이름 열 뒤에서 세그먼트와 글자 시작선을 공유하는 팝업.
public struct ValuePopup: View {
    let inSettings: Bool
    let fillsRow: Bool
    let label: String
    let value: String
    let dot: NSImage?
    let theme: Theme
    let menuOffset: CGSize
    let makeMenu: () -> NSMenu
    let choose: (NSMenuItem) -> Void

    public init(label: String, value: String, dot: NSImage? = nil, theme: Theme, inSettings: Bool = false, fillsRow: Bool = false,
                menuOffset: CGSize? = nil, makeMenu: @escaping () -> NSMenu, choose: @escaping (NSMenuItem) -> Void) {
        self.menuOffset = menuOffset ?? CGSize(width: 0, height: theme.shape(.borderWidth))
        self.fillsRow = fillsRow
        self.inSettings = inSettings
        self.label = label
        self.value = value
        self.dot = dot
        self.theme = theme
        self.makeMenu = makeMenu
        self.choose = choose
    }

    public var body: some View {
        ValuePopupHost(popup: self).fixedSize(horizontal: !fillsRow, vertical: true)
    }

    private struct ValuePopupHost: NSViewRepresentable {
        let popup: ValuePopup
        func makeNSView(context: Context) -> ValueButton { ValueButton(theme: popup.theme, inSettings: popup.inSettings) }
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: ValueButton, context: Context) -> CGSize? {
            let size = nsView.intrinsicContentSize
            return CGSize(width: popup.fillsRow ? proposal.width ?? size.width : size.width, height: size.height)
        }
        func updateNSView(_ button: ValueButton, context: Context) {
            button.isEnabled = context.environment.isEnabled
            button.title = popup.value
            button.image = popup.dot
            button.font = popup.theme.nsFont(.body, size: popup.theme.tokens.textStyle(popup.inSettings ? .micro : .ui).size)
            button.setAccessibilityLabel(popup.label)
            button.setAccessibilityValue(popup.value)
            button.menu = popup.makeMenu()
            button.choose = popup.choose
            button.menuOffset = popup.menuOffset
            button.prepareMenu()
            button.invalidateIntrinsicContentSize()
            button.needsDisplay = true
        }
    }
}

class ValueButton: NSButton {
    let theme: Theme
    var choose: ((NSMenuItem) -> Void)?
    var menuOffset: CGSize = .zero
    var popup: SettingsValueMenu?
    var hovered = false
    let inSettings: Bool
    init(theme: Theme, inSettings: Bool) {
        self.inSettings = inSettings
        self.theme = theme
        super.init(frame: .zero)
        isBordered = false
        target = self
        action = #selector(openChoices)
        setAccessibilityRole(.popUpButton)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var text: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font ?? theme.nsFont(.body), .foregroundColor: theme.nsColor(.text)])
    }
    private var textX: CGFloat {
        (inSettings ? theme.component(.settingsSegmentPad) : 0) + (image.map { $0.size.width + theme.space(.sp2) } ?? 0)
    }
    private var chevronWidth: CGFloat { theme.component(.settingsChevronWidth) }
    private var valueGap: CGFloat { theme.component(inSettings ? .chromeGap : .badgePad) }
    override var intrinsicContentSize: NSSize {
        NSSize(width: textX + ceil(text.size().width) + valueGap + chevronWidth + (inSettings ? theme.space(.sp2) : 0),
               height: theme.component(inSettings ? .controlHeight : .connectHeight))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if inSettings || hovered || isHighlighted {
            theme.nsColor(inSettings && !hovered && !isHighlighted && popup?.isVisible != true ? .connectFill : .hover).setFill()
            let radius = theme.shape(.controlRadius)
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        if let image {
            image.draw(in: CGRect(x: inSettings ? theme.component(.settingsSegmentPad) : 0, y: (bounds.height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
        }
        let arrowX = bounds.maxX - chevronWidth - (inSettings ? theme.space(.sp2) : 0)
        MenuText.draw(title, font: font ?? theme.nsFont(.body), color: theme.nsColor(.text),
                      x: textX, width: arrowX - valueGap - textX, center: bounds.midY, flipped: isFlipped)
        drawChevron(at: arrowX, single: inSettings)
    }
    func drawChevron(at x: CGFloat, single: Bool) {
        let width = theme.component(.settingsChevronWidth)
        let height = theme.component(.settingsChevronHeight)
        let y = bounds.midY - (single ? (isFlipped ? 1 : -1) * height / 3 : 0)
        let path = NSBezierPath()
        for sign: CGFloat in (single ? [isFlipped ? 1 : -1] : [-1, 1]) {
            path.move(to: NSPoint(x: x, y: y + sign * height / 6))
            path.line(to: NSPoint(x: x + width / 2, y: y + sign * height / 2))
            path.line(to: NSPoint(x: x + width, y: y + sign * height / 6))
        }
        theme.nsColor(.text2).setStroke()
        path.lineWidth = theme.component(.iconStroke)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
    func prepareMenu() {
        for item in menu?.items ?? [] where item.isEnabled && !item.isSeparatorItem {
            item.target = self
            item.action = #selector(selectChoice(_:))
        }
    }
    @objc private func selectChoice(_ sender: NSMenuItem) { choose?(sender) }
    var usesFloatingMenu: Bool { inSettings }
    func popupVisibilityChanged() {}
    @objc func openChoices() {
        guard let menu else { return }
        if usesFloatingMenu {
            if let popup, popup.isVisible {
                popup.close()
                return
            }
            popup = SettingsValueMenu(menu: menu, anchor: self, offset: menuOffset)
            popup?.onDismiss = { [weak self] in
                self?.popup = nil
                self?.popupVisibilityChanged()
            }
            popupVisibilityChanged()
            needsDisplay = true
        }
        else { menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: bounds.midY), in: self) }
    }
}
