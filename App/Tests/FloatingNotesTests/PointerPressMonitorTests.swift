import AppKit
import Testing
@testable import FloatingNotes

/// 마우스 누름의 처음과 끝을 알리는 감시(`PointerPressMonitor`). 이벤트는 이 프로세스 안에서 만들어
/// `NSApplication.sendEvent`로 넘긴다(시스템에 이벤트를 보내지 않는다).
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct PointerPressMonitorTests {
    private func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    /// 누름은 이벤트가 전달되기 전에, 끝은 뗀 이벤트의 처리가 끝난 다음 차례에 알린다.
    @Test func reportsThePressBeforeDispatchAndTheEndAfterIt() async throws {
        var events: [String] = []
        let monitor = PointerPressMonitor(began: { events.append("began") }, ended: { events.append("ended") })
        defer { withExtendedLifetime(monitor) {} }

        NSApplication.shared.sendEvent(try mouseEvent(.leftMouseDown))
        #expect(events == ["began"])
        NSApplication.shared.sendEvent(try mouseEvent(.leftMouseUp))
        // 뗀 이벤트를 처리하는 동안(버튼의 동작이 도는 동안)에는 아직 끝나지 않았다.
        #expect(events == ["began"])
        let deadline = Date().addingTimeInterval(3)
        while events.count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(events == ["began", "ended"])
    }
}
