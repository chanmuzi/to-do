import AppKit

/// 실제 마우스 이벤트(누름과 뗌)를 만들어 창의 이벤트 경로(`NSWindow.sendEvent`)로 넣는다.
/// 버튼의 동작을 직접 부르지 않고, 사용자가 누를 때와 같은 길로 간다. 시스템에 이벤트를 보내지 않는다.
@MainActor
enum RealClick {
    private final class Flag: @unchecked Sendable {
        var isSet = false
    }

    struct Outcome: Equatable {
        /// 누른 이벤트를 처리하는 동안 줄에 넣어 둔 뗀 이벤트가 사라졌다(창이 끌기나 크기 조절로 가져갔다).
        var swallowedByTracking: Bool
    }

    static func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    /// 뷰의 한가운데를 한 번 누른다.
    @discardableResult
    static func click(_ view: NSView, via send: ((NSEvent) -> Void)? = nil) -> Outcome {
        click(at: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil), in: view.window!, via: send)
    }

    /// 창 좌표의 한 점을 한 번 누른다.
    /// - Parameter send: 이벤트를 넣는 길. 주지 않으면 `window.sendEvent`.
    ///
    /// 누름이 창의 추적 루프(끌기, 크기 조절)로 들어가면 `sendEvent`가 뗀 이벤트를 기다리며 돌아오지 않는다.
    /// 그때를 알아채려고 추적 중에도 도는 시계를 걸어 두고, 시계가 돌면 뗀 이벤트를 줄에 넣어 루프를 끝낸다.
    /// (뗀 이벤트를 미리 줄에 넣어 두고 꺼내는 방식은 그 뒤에 시험 프로세스가 말없이 끝나 쓰지 않는다.)
    @discardableResult
    static func click(at point: NSPoint, in window: NSWindow, via send: ((NSEvent) -> Void)? = nil) -> Outcome {
        let send = send ?? { window.sendEvent($0) }
        let tracked = Flag()
        let number = window.windowNumber
        let watchdog = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                tracked.isSet = true
                let up = NSEvent.mouseEvent(
                    with: .leftMouseUp, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 0
                )
                if let up { NSApplication.shared.postEvent(up, atStart: true) }
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        send(event(.leftMouseDown, at: point, in: window))
        watchdog.invalidate()
        guard !tracked.isSet else { return Outcome(swallowedByTracking: true) }
        send(event(.leftMouseUp, at: point, in: window))
        return Outcome(swallowedByTracking: false)
    }
}
