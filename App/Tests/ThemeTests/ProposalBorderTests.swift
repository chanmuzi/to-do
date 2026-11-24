import AppKit
import SwiftUI
import Testing
@testable import Theme

@MainActor @Suite struct ProposalBorderTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func pendingCardHasAContinuousEdgeAndClearCenter(scheme: ColorScheme) throws {
        let theme = try Theme.bundled()
        func image(pending: Bool) throws -> NSBitmapImageRep {
            let view = Color.clear.frame(width: 64, height: 40)
                .proposalBackground(theme, pending: pending, radius: theme.shape(.windowRadius))
                .environment(\.colorScheme, scheme)
            return NSBitmapImageRep(cgImage: try #require(ImageRenderer(content: view).cgImage))
        }
        let pending = try image(pending: true)
        #expect(pending.colorAt(x: 32, y: 20)?.alphaComponent == 0)
        // 모서리 곡선이 직선에 닿는 픽셀은 안티앨리어싱으로 일부만 채워진다.
        for x in 10..<54 {
            #expect((pending.colorAt(x: x, y: 0)?.alphaComponent ?? 0) > 0.95)
            #expect((pending.colorAt(x: x, y: 39)?.alphaComponent ?? 0) > 0.95)
        }
        for y in 10..<30 {
            #expect((pending.colorAt(x: 0, y: y)?.alphaComponent ?? 0) > 0.95)
            #expect((pending.colorAt(x: 63, y: y)?.alphaComponent ?? 0) > 0.95)
        }
        #expect(pending.colorAt(x: 10, y: 0) != pending.colorAt(x: 53, y: 39))
        let settled = try image(pending: false)
        let center = settled.colorAt(x: 32, y: 20)
        #expect(center?.alphaComponent == 1)
        #expect(settled.colorAt(x: 32, y: 0) == center)
    }
}
