import CoreGraphics
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct HeightTransitionTests {
    private let ease: BezierCurve

    init() throws {
        ease = try ThemeTokens.bundled().motion.curve
    }

    @Test func easeCurveStartsAndEndsExactlyAndOnlyMovesForward() {
        #expect(ease.progress(at: 0) == 0)
        #expect(ease.progress(at: 1) == 1)
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(ease.progress(at:))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        // CSS의 ease(.25,.1,.25,1)는 절반의 시간에 약 80%를 간다.
        #expect(abs(ease.progress(at: 0.5) - 0.8024) < 0.001)
    }

    @Test func heightRunsFromStartToTargetOverTheDuration() {
        let transition = HeightTransition(from: 77, to: 277, duration: 0.18, curve: ease)
        #expect(transition.height(at: 0) == 77)
        #expect(transition.height(at: 0.09) > 177)
        #expect(transition.height(at: 0.09) < 277)
        #expect(transition.height(at: 0.18) == 277)
        #expect(transition.height(at: 5) == 277)
    }

    @Test func shrinkingWorksTheSameWay() {
        let transition = HeightTransition(from: 277, to: 77, duration: 0.18, curve: ease)
        #expect(transition.height(at: 0) == 277)
        #expect(transition.height(at: 0.09) < 177)
        #expect(transition.height(at: 0.18) == 77)
    }

    @Test func zeroDurationJumpsToTheTarget() {
        let transition = HeightTransition(from: 77, to: 277, duration: 0, curve: ease)
        #expect(transition.isInstant)
        #expect(transition.height(at: 0) == 277)
    }
}
