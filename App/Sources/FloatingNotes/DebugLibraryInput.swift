#if DEBUG
import AppKit

/// 이 프로세스의 라이브러리 창에만 입력한다. 좌표는 창 내용의 왼쪽 위부터 pt 단위다.
enum DebugLibraryInput {
    static func scrollToEnd(_ scroll: NSScrollView) {
        guard let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let bounds = clip.documentRect
        let y = document.isFlipped ? max(bounds.minY, bounds.maxY - clip.bounds.height) : bounds.minY
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    private static weak var hovered: NSView?
    static func state(window: NSWindow?) -> [String: Any] {
        guard let window else { return [:] }
        func views(_ view: NSView) -> [[String: Any]] {
            let rect = view.convert(view.bounds, to: window.contentView)
            return [["class": String(describing: type(of: view)), "frame": NSStringFromRect(rect),
                     "label": view.accessibilityLabel() ?? "", "focusRing": view.focusRingType.rawValue,
                     "firstResponder": window.firstResponder === view]]
                + view.subviews.flatMap(views)
        }
        return ["firstResponder": window.firstResponder.map { String(describing: type(of: $0)) } ?? "",
                "firstResponderLabel": (window.firstResponder as? NSView)?.accessibilityLabel() ?? "",
                "defaultButton": window.defaultButtonCell != nil,
                "views": window.contentView.map(views) ?? []]
    }
    static func mouse(window: NSWindow, point: String, action: String) {
        let xy = point.split(separator: ",").compactMap { Double($0) }
        guard xy.count == 2, let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let location = view.convert(NSPoint(x: xy[0], y: view.isFlipped ? xy[1] : view.bounds.height - xy[1]), to: nil)
        if action == "hover" {
            if let event = NSEvent.enterExitEvent(with: .mouseEntered, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                let hit = view.hitTest(view.superview!.convert(location, from: nil))
                hovered?.mouseExited(with: event)
                hit?.mouseEntered(with: event)
                hovered = hit
            }
        }
        let types: [NSEvent.EventType] = action == "hover" ? [.mouseMoved] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: action == "double" ? 2 : 1, pressure: 1) else { return }
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }

    static func key(window: NSWindow, key: String) {
        let keys: [String: (String, UInt16)] = ["return": ("\r", 36), "down": ("\u{F701}", 125),
            "up": ("\u{F700}", 126), "tab": ("\t", 48), "escape": ("\u{1B}", 53)]
        guard let (characters, code) = keys[key], let event = NSEvent.keyEvent(with: .keyDown,
            location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        window.sendEvent(event)
    }
}
#endif
