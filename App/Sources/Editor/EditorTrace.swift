import Foundation
import os

/// Instruments와 성능 테스트가 같은 동기 구간을 잰다.
nonisolated package enum EditorTrace {
    private static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "local.floating-notes", category: "editor")
    @TaskLocal static var observe: (@Sendable (StaticString, Duration) -> Void)?

    struct Interval {
        let state: OSSignpostIntervalState?
        let start: ContinuousClock.Instant?
    }

    static func begin(_ name: StaticString) -> Interval {
        Interval(state: signposter.isEnabled ? signposter.beginInterval(name, id: signposter.makeSignpostID()) : nil,
                 start: observe == nil ? nil : .now)
    }

    static func end(_ name: StaticString, _ interval: Interval) {
        if let state = interval.state { signposter.endInterval(name, state) }
        if let start = interval.start { observe?(name, start.duration(to: .now)) }
    }

    package static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let interval = begin(name)
        defer { end(name, interval) }
        return body()
    }
}
