import AppKit
import Theme

/// 글자와 AppKit 버튼이 같은 치수로 오른쪽 자리를 나눈다.
struct LibraryRowActionLayout {
    let theme: Theme
    let allowsPin: Bool

    private var side: CGFloat { theme.component(.iconButton) }
    private var gap: CGFloat { theme.component(.iconButtonGap) }
    private var trailing: CGFloat { theme.component(.libraryRowLeading) }

    var textTrailing: CGFloat {
        trailing + side + (allowsPin ? side + gap : 0) + theme.component(.chromePaddingEnd)
    }

    func frames(in bounds: NSRect, revealed: Bool) -> (pin: NSRect, more: NSRect) {
        let more = NSRect(x: bounds.maxX - trailing - side, y: bounds.midY - side / 2, width: side, height: side)
        return (revealed ? more.offsetBy(dx: -side - gap, dy: 0) : more, more)
    }
}

final class LibraryRowActionButton: NSButton {
    var hoverColor: NSColor?
    var radius: CGFloat = 0
    var showsHover = false {
        didSet { if oldValue != showsHover { needsDisplay = true } }
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        focusRingType = .none
        setAccessibilityElement(true)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        if showsHover {
            hoverColor?.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
}
