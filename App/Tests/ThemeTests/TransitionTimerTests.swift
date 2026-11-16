import Foundation
import Testing
import Theme

@Suite @MainActor struct TransitionTimerTests {
    /// 시간이 0이면("동작 줄이기") 기다리지 않고 그 자리에서 한다.
    @Test func zeroDurationRunsSynchronously() {
        var ran = false
        let task = TransitionTimer.after(0) { ran = true }
        #expect(ran)
        #expect(task == nil)
    }

    /// 시간이 지나면 움직임과 상관없이 한다. 그 전에는 하지 않는다.
    @Test func runsAfterTheDuration() async throws {
        var ran = false
        let task = try #require(TransitionTimer.after(0.05) { ran = true })
        #expect(!ran)
        await task.value
        #expect(ran)
    }

    /// 그사이 취소하면 하지 않는다.
    @Test func cancelledTimerDoesNotRun() async throws {
        var ran = false
        let task = try #require(TransitionTimer.after(0.05) { ran = true })
        task.cancel()
        await task.value
        try await Task.sleep(for: .milliseconds(80))
        #expect(!ran)
    }
}
