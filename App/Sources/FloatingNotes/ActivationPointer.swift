import AppKit

/// 창 제목이나 다른 앱의 식별자 없이 현재 누름 대상과 시스템 입력의 경과 시간만 읽는다.
struct ActivationPointer {
    let windowNumber: Int
    let window: ActivationDecision.WindowKind
    let mouseAge: TimeInterval
    let keyAge: TimeInterval

    init(library: NSWindow?, at point: NSPoint = NSEvent.mouseLocation) {
        mouseAge = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        keyAge = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        windowNumber = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        if windowNumber <= 0 {
            window = .none
        } else if let own = NSApp.window(withWindowNumber: windowNumber) {
            window = own === library ? .library : .floatWindow
        } else {
            window = .external
        }
    }
}
