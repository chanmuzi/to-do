import AppKit
import Theme

final class ScheduleLineButton: NSButton {
    let theme: Theme
    var marker: ScheduleLineMarker
    var onOpen: ((String?, NSView) -> Void)?
    var hovered = false {
        didSet {
            guard oldValue != hovered else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(EditorController.reduceMotion ? 0 : theme.motion.duration)
            CATransaction.setAnimationTimingFunction(theme.motion.timingFunction)
            layer?.backgroundColor = (hovered ? theme.rgba(.hover).nsColor : .clear).cgColor
            CATransaction.commit()
        }
    }

    init(theme: Theme, marker: ScheduleLineMarker) {
        self.theme = theme
        self.marker = marker
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.shape(.controlRadius)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        isBordered = false
        title = ""
        setAccessibilityLabel(marker.label)
        target = self
        action = #selector(openSchedule)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc func openSchedule() { onOpen?(marker.selectedID, self) }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func draw(_ dirtyRect: NSRect) {
        let diameter = theme.component(.noticeDot)
        theme.nsColor(marker.isImminent ? .warn : .text3).setFill()
        NSBezierPath(ovalIn: CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                                    width: diameter, height: diameter)).fill()
    }
}

extension EditorController {
    func hasScheduleMarker(at line: Int) -> Bool {
        guard let button = scheduleButtons[line], document.lines.indices.contains(line) else { return false }
        return document.string(in: document.lines[line].range) == button.marker.text
    }

    func updateScheduleButtons(_ markers: [Int: ScheduleLineMarker]) {
        let changed = Set(scheduleButtons.keys).union(markers.keys).filter {
            scheduleButtons[$0]?.marker.text != markers[$0]?.text && document.lines.indices.contains($0)
        }
        for line in scheduleButtons.keys where markers[line] == nil {
            scheduleButtons.removeValue(forKey: line)?.removeFromSuperview()
        }
        for (line, marker) in markers {
            if let button = scheduleButtons[line] {
                if button.marker != marker {
                    button.marker = marker
                    button.setAccessibilityLabel(marker.label)
                    button.needsDisplay = true
                }
            } else {
                let button = ScheduleLineButton(theme: theme, marker: marker)
                button.onOpen = { [weak self] id, anchor in self?.onOpenSchedule?(id, anchor) }
                textView.addSubview(button)
                scheduleButtons[line] = button
            }
        }
        if changed.isEmpty {
            layoutScheduleButtons()
        } else {
            for line in changed { invalidate(lines: line..<(line + 1)) }
            reportContentHeight()
        }
    }

    func layoutScheduleButtons() {
        guard !scheduleButtons.isEmpty else { return }
        let hidden = FoldState.hiddenLines(document, folded: folded)
        let side = theme.component(.noteTopButtonSize)
        for (line, button) in scheduleButtons {
            guard !hidden.contains(line), hasScheduleMarker(at: line),
                  let spot = caretSpot(document.lines[line].start, lineIndex: line) else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            let rect = CGRect(x: textView.bounds.maxX - theme.docPadding.trailing - side,
                              y: textView.textContainerOrigin.y + spot.line.midY - side / 2,
                              width: side, height: side)
            if button.frame != rect { button.frame = rect }
        }
    }
}
