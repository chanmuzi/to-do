import AppKit

/// 이 앱의 창에 온 마우스 누름의 처음과 끝을 알리는 곳.
///
/// 노트 찾기가 떠 있을 때 노트의 돋보기를 누르면, 누르는 순간(mouseDown) 노트 창이 키 창이 되어 노트 찾기가
/// 물러나며 닫히고, 떼는 순간(mouseUp) 돋보기가 "노트 찾기 열기"를 보낸다. 둘이 한 누름이라는 것을
/// `QuickPanels`가 알아야 다시 띄우지 않는다. 이벤트가 창에 전달되기 전에 불리는 앱 안의 감시로 안다.
/// 시스템에 이벤트를 보내거나 다른 앱의 이벤트를 보지 않는다.
final class PointerPressMonitor {
    private var monitors: [Any] = []

    /// - Parameters:
    ///   - began: 누른 이벤트가 창에 전달되기 직전.
    ///   - ended: 뗀 이벤트의 처리가 끝난 뒤(메인 큐의 다음 차례).
    init(began: @escaping () -> Void, ended: @escaping () -> Void,
         inactiveWindowPress: @escaping (NSWindow, TimeInterval) -> Void = { _, _ in },
         windowPress: @escaping (NSWindow) -> Void = { _ in }) {
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let ups: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: downs) { event in
                if event.type == .leftMouseDown, !NSApp.isActive,
                   !event.modifierFlags.contains(.command), let window = event.window {
                    inactiveWindowPress(window, event.timestamp)
                }
                if event.type == .leftMouseDown, let window = event.window { windowPress(window) }
                began()
                return event
            },
            NSEvent.addLocalMonitorForEvents(matching: ups) { event in
                // 이 감시는 이벤트가 전달되기 전에 불린다. 버튼의 동작이 끝난 뒤에 알리도록 한 차례 미룬다.
                DispatchQueue.main.async { ended() }
                return event
            },
        ].compactMap { $0 }
    }

    isolated deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }
}
