import AppKit
import SwiftUI

/// 이름 열 뒤에서 세그먼트와 글자 시작선을 공유하는 팝업.
public struct ValuePopup: View {
    let inSettings: Bool
    let label: String
    let value: String
    let dot: NSImage?
    let theme: Theme
    let menuOffset: CGSize
    let makeMenu: () -> NSMenu
    let choose: (NSMenuItem) -> Void

    public init(label: String, value: String, dot: NSImage? = nil, theme: Theme, inSettings: Bool = false,
                menuOffset: CGSize? = nil, makeMenu: @escaping () -> NSMenu, choose: @escaping (NSMenuItem) -> Void) {
        self.menuOffset = menuOffset ?? CGSize(width: 0, height: theme.shape(.borderWidth))
        self.inSettings = inSettings
        self.label = label
        self.value = value
        self.dot = dot
        self.theme = theme
        self.makeMenu = makeMenu
        self.choose = choose
    }

    public var body: some View {
        let firstLetter = theme.component(.iconButtonGap) + theme.space(.sp3)
        let leading = firstLetter - theme.component(.chromePaddingEnd)
            - (dot.map { $0.size.width + theme.component(.badgePad) } ?? 0)
        ValuePopupHost(popup: self).fixedSize().padding(.leading, inSettings ? 0 : leading)
    }

    private struct ValuePopupHost: NSViewRepresentable {
        let popup: ValuePopup
        func makeNSView(context: Context) -> ValueButton { ValueButton(theme: popup.theme, inSettings: popup.inSettings) }
        func updateNSView(_ button: ValueButton, context: Context) {
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

private final class ValueButton: NSButton {
    let theme: Theme
    var choose: ((NSMenuItem) -> Void)?
    var menuOffset: CGSize = .zero
    private var popup: SettingsValueMenu?
    private var hovered = false
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
        theme.component(inSettings ? .settingsSegmentPad : .chromePaddingEnd) + (image.map { $0.size.width + theme.component(.badgePad) } ?? 0)
    }
    private var chevronWidth: CGFloat { theme.component(inSettings ? .settingsChevronWidth : .menuDot) }
    private var valueGap: CGFloat { theme.component(inSettings ? .chromeGap : .badgePad) }
    override var intrinsicContentSize: NSSize {
        NSSize(width: textX + ceil(text.size().width) + valueGap + chevronWidth + (inSettings ? theme.space(.sp2) : theme.component(.chromePaddingEnd)),
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
            image.draw(in: CGRect(x: theme.component(inSettings ? .settingsSegmentPad : .chromePaddingEnd), y: (bounds.height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
        }
        let value = text
        value.draw(at: NSPoint(x: textX, y: (bounds.height - value.size().height) / 2))
        let width = chevronWidth, height = inSettings ? theme.component(.settingsChevronHeight) : theme.space(.sp3)
        let x = textX + ceil(value.size().width) + valueGap, y = bounds.midY - (inSettings ? (isFlipped ? 1 : -1) * height / 3 : 0)
        let path = NSBezierPath()
        for sign: CGFloat in (inSettings ? [isFlipped ? 1 : -1] : [-1, 1]) {
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
    @objc private func openChoices() {
        guard let menu else { return }
        if inSettings {
            if popup?.isVisible == true { popup?.close() }
            popup = SettingsValueMenu(menu: menu, anchor: self, offset: menuOffset)
            needsDisplay = true
        }
        else { menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: bounds.midY), in: self) }
    }
}
