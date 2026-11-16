import CoreGraphics
import Testing
@testable import NotePanel

@Suite @MainActor struct NoteSizePolicyTests {
    private let policy = NoteSizePolicy(
        defaultWidth: 340, minWidth: 260, maxWidth: 560, chromeHeight: 29, minBodyHeight: 48,
        maxScreenFraction: 0.7
    )

    @Test func widthStaysWithinTheLimits() {
        #expect(policy.clampedWidth(100) == 260)
        #expect(policy.clampedWidth(400) == 400)
        #expect(policy.clampedWidth(900) == 560)
    }

    @Test func heightFollowsTheContent() {
        #expect(policy.windowHeight(contentHeight: 148, screenHeight: 1000) == 177)
    }

    @Test func contentShorterThanTheMinimumBodyKeepsTheMinimum() {
        #expect(policy.windowHeight(contentHeight: 0, screenHeight: 1000) == 77)
        #expect(policy.minHeight == 77)
    }

    @Test func heightStopsAtSeventyPercentOfTheScreen() {
        #expect(policy.windowHeight(contentHeight: 5000, screenHeight: 1000) == 700)
    }

    @Test func heightStopsAtTheBottomOfTheScreenWhenTheNoteSitsLow() {
        #expect(policy.windowHeight(contentHeight: 5000, screenHeight: 1000, roomBelowTop: 300) == 300)
        #expect(policy.windowHeight(contentHeight: 100, screenHeight: 1000, roomBelowTop: 300) == 129)
        #expect(policy.windowHeight(contentHeight: 5000, screenHeight: 1000, roomBelowTop: 20) == 77)
    }

    @Test func aTinyScreenNeverShrinksTheNoteBelowItsMinimum() {
        #expect(policy.windowHeight(contentHeight: 5000, screenHeight: 50) == 77)
    }

    @Test func frameGrowsDownwardFromAFixedTopEdge() {
        let current = CGRect(x: 100, y: 623, width: 340, height: 77)
        let grown = policy.frame(current: current, top: current.maxY, contentHeight: 248, screenHeight: 1000)
        #expect(grown.maxY == current.maxY)
        #expect(grown.minX == current.minX)
        #expect(grown.width == current.width)
        #expect(grown.height == 277)

        let shrunk = policy.frame(current: grown, top: grown.maxY, contentHeight: 48, screenHeight: 1000)
        #expect(shrunk == current)
    }
}
