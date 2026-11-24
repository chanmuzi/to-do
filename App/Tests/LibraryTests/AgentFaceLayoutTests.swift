import AppKit
import SwiftUI
import Testing
@testable import Library
import Theme

@MainActor @Suite struct AgentFaceLayoutTests {
    private final class CountingHost: LibraryHostingView<AgentFace> {
        var layoutCount = 0
        override func layout() {
            layoutCount += 1
            super.layout()
        }
    }

    @Test func animatedFaceDoesNotRelayoutLibrary() async throws {
        let theme = try Theme.bundled()
        let host = CountingHost(rootView: AgentFace(theme: theme, state: .read))
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 32, height: 32),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let initial = host.layoutCount
        #expect(initial > 0)
        try await Task.sleep(for: .milliseconds(350))
        #expect(host.layoutCount == initial)
    }
}
