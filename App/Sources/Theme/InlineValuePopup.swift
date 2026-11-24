import SwiftUI

/// 입력 칸의 메뉴도 설정과 같은 비활성 패널과 선택 행을 쓴다.
package struct InlineValuePopup: NSViewRepresentable {
    package let theme: Theme
    package let name: String
    package let detail: String?
    package let visible: Bool
    package let lineSpace: CommandLineSpace?
    package let label: String
    package let makeMenu: () -> NSMenu
    package let choose: (NSMenuItem) -> Void

    package init(theme: Theme, name: String, detail: String?, visible: Bool, lineSpace: CommandLineSpace? = nil, label: String,
                 makeMenu: @escaping () -> NSMenu, choose: @escaping (NSMenuItem) -> Void) {
        self.lineSpace = lineSpace
        self.theme = theme
        self.name = name
        self.detail = detail
        self.visible = visible
        self.label = label
        self.makeMenu = makeMenu
        self.choose = choose
    }

    package func makeNSView(context: Context) -> NSButton { InlineValueButton(theme: theme, inSettings: false) }
    package func updateNSView(_ view: NSButton, context: Context) {
        guard let button = view as? InlineValueButton else { return }
        button.font = theme.nsFont(.body, size: theme.component(.agentModelFont))
        button.title = name
        button.detail = detail
        button.lineSpace = lineSpace
        button.visible = visible
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(detail.map { name + " " + $0 } ?? name)
        button.makeChoices = makeMenu
        button.choose = choose
        button.updateAppearance()
    }
    package func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(size.width, proposal.width ?? size.width), height: size.height)
    }
}

private final class InlineValueButton: ValueButton {
    override var usesFloatingMenu: Bool { true }
    var detail: String?
    var lineSpace: CommandLineSpace?
    var visible = true
    var makeChoices: (() -> NSMenu)?
    private var shown: Bool { popup?.isVisible == true || (fits && (visible || window?.firstResponder === self)) }
    private var gap: CGFloat { theme.component(.captureValueGap) }
    private var labelFont: NSFont { theme.nsFont(.body, size: theme.component(.agentModelFont)) }
    private func text(_ string: String, _ color: ColorToken) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [.font: labelFont, .foregroundColor: theme.nsColor(color), .paragraphStyle: paragraph])
    }
    private var detailWidth: CGFloat { detail.map { ceil(text($0, .text3).size().width) + gap } ?? 0 }
    private var fixedWidth: CGFloat { detailWidth + gap * 3 + theme.component(.settingsChevronWidth) }
    private var buttonWidth: CGFloat {
        let natural = min(theme.component(.agentModelNameMax), ceil(text(title, .text2).size().width)) + fixedWidth
        guard let space = lineSpace else { return natural }
        return min(natural, space.fieldWidth / 2, space.fieldWidth - space.placeholderEnd - gap)
    }
    private var fits: Bool {
        guard let space = lineSpace else { return true }
        let minimumName = ceil(text("…", .text2).size().width)
        return buttonWidth >= fixedWidth + minimumName && space.lineEnd + gap <= space.fieldWidth - buttonWidth
    }
    override var intrinsicContentSize: NSSize {
        let height = ceil(text(title, .text2).size().height) + theme.component(.agentModelInsetY) * 2
        guard fits || popup?.isVisible == true else { return .zero }
        let availableHeight = lineSpace.flatMap { $0.multiline ? $0.lineHeight : nil } ?? height
        return NSSize(width: shown ? buttonWidth : theme.shape(.borderWidth), height: min(height, availableHeight))
    }
    override func hitTest(_ point: NSPoint) -> NSView? { shown ? super.hitTest(point) : nil }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { popup?.close(); popup = nil }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard shown else { return }
        if lineSpace != nil {
            let color = theme.nsColor(.surface)
            let fade = CGRect(x: bounds.minX, y: bounds.minY, width: gap, height: bounds.height)
            NSGradient(starting: color.withAlphaComponent(0), ending: color)?.draw(in: fade, angle: 0)
            color.setFill()
            bounds.divided(atDistance: gap, from: .minXEdge).remainder.fill()
        }
        if hovered || isHighlighted || popup?.isVisible == true {
            theme.nsColor(.hover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: theme.shape(.controlRadius), yRadius: theme.shape(.controlRadius)).fill()
        }
        let name = text(title, .text2)
        let height = ceil(name.size().height)
        let y = (bounds.height - height) / 2
        let side = theme.component(.settingsChevronWidth)
        let nameWidth = max(0, bounds.width - gap * 3 - side - detailWidth)
        name.draw(in: NSRect(x: gap, y: y, width: nameWidth, height: height))
        if let detail { text(detail, .text3).draw(at: .init(x: gap * 2 + nameWidth, y: y)) }
        drawChevron(at: bounds.maxX - gap - side, single: true)
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateAppearance() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateAppearance() }
        return accepted
    }
    override var acceptsFirstResponder: Bool { fits }
    override func keyDown(with event: NSEvent) {
        if [36, 76, 49].contains(event.keyCode) { openChoices() } else { super.keyDown(with: event) }
    }
    override func openChoices() {
        if popup?.isVisible != true {
            guard fits else { return }
            menu = makeChoices?()
            prepareMenu()
        }
        super.openChoices()
    }
    override func popupVisibilityChanged() { updateAppearance() }
    func updateAppearance() {
        setAccessibilityElement(fits || popup?.isVisible == true)
        wantsLayer = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : theme.motion.duration)
        CATransaction.setAnimationTimingFunction(theme.motion.timingFunction)
        layer?.opacity = shown ? 1 : 0
        CATransaction.commit()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}
