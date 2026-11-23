#if DEBUG
import AppKit

/// 자기 앱 뷰의 실제 배치와 글꼴을 스냅숏 옆에 기록한다. 시스템 화면이나 입력은 읽지 않는다.
enum DebugViewAudit {
    static func hover(_ root: NSView, label: String) {
        func send(_ type: NSEvent.EventType, to view: NSView) {
            guard let window = view.window,
                  let event = NSEvent.enterExitEvent(with: type,
                    location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
            if type == .mouseEntered { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
        }
        var targets: [NSView] = []
        func visit(_ view: NSView) {
            if view.accessibilityLabel() == label || String(describing: type(of: view)) == label {
                targets.append(view)
            } else {
                send(.mouseExited, to: view)
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        // 하위 이미지가 상위 버튼으로 전달하는 이탈까지 마친 뒤 대상에 진입시킨다.
        targets.forEach { send(.mouseEntered, to: $0) }
    }

    static func write(_ root: NSView, to url: URL) throws {
        func inspect(_ view: NSView) -> [String: Any] {
            var row: [String: Any] = [
                "class": String(describing: type(of: view)),
                "frame": NSStringFromRect(view.convert(view.bounds, to: root)),
                "localFrame": NSStringFromRect(view.frame),
                "hidden": view.isHidden, "alpha": view.alphaValue,
                "label": view.accessibilityLabel() ?? "",
                "radius": view.layer?.cornerRadius ?? 0,
                "children": view.subviews.map(inspect),
            ]
            if let field = view as? NSTextField {
                row["text"] = field.stringValue
                row["font"] = field.font?.fontName ?? ""
                row["fontSize"] = field.font?.pointSize ?? 0
            }
            if let image = view as? NSImageView {
                row["imageSize"] = NSStringFromSize(image.image?.size ?? .zero)
            }
            return row
        }
        root.layoutSubtreeIfNeeded()
        try JSONSerialization.data(withJSONObject: inspect(root), options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
#endif
