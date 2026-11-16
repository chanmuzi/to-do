import CoreGraphics
import Testing
@testable import NotePanel

@Suite @MainActor struct WindowPlacementTests {
    private let placement = WindowPlacement(gap: 12, cascade: 28, margin: 24)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 340, height: 77)

    @Test func firstNoteGoesToTheTopRightCorner() {
        let frame = placement.initialFrame(size: size, visibleFrame: screen, occupied: [])
        #expect(frame == CGRect(x: 1076, y: 799, width: 340, height: 77))
    }

    @Test func initialFrameCascadesAwayFromANoteInTheSameSpot() {
        let first = placement.initialFrame(size: size, visibleFrame: screen, occupied: [])
        let second = placement.initialFrame(size: size, visibleFrame: screen, occupied: [first])
        #expect(second == first.offsetBy(dx: -28, dy: -28))
        let third = placement.initialFrame(size: size, visibleFrame: screen, occupied: [first, second])
        #expect(third == first.offsetBy(dx: -56, dy: -56))
    }

    @Test func newNoteOpensToTheRightWithTopsAligned() {
        let anchor = CGRect(x: 200, y: 500, width: 340, height: 200)
        let frame = placement.frame(nextTo: anchor, size: size, visibleFrame: screen, occupied: [anchor])
        #expect(frame.minX == anchor.maxX + 12)
        #expect(frame.maxY == anchor.maxY)
        #expect(frame.size == size)
    }

    @Test func newNoteFallsBackToTheLeftWhenTheRightIsOffScreen() {
        let anchor = CGRect(x: 1000, y: 500, width: 340, height: 200)
        let frame = placement.frame(nextTo: anchor, size: size, visibleFrame: screen, occupied: [anchor])
        #expect(frame.maxX == anchor.minX - 12)
        #expect(frame.maxY == anchor.maxY)
    }

    @Test func newNoteSkipsASideThatAnotherNoteOccupies() {
        let anchor = CGRect(x: 500, y: 500, width: 340, height: 200)
        let right = CGRect(x: 852, y: 600, width: 340, height: 100)
        let frame = placement.frame(nextTo: anchor, size: size, visibleFrame: screen, occupied: [anchor, right])
        #expect(frame.maxX == anchor.minX - 12)
    }

    @Test func newNoteCascadesWhenNeitherSideIsFree() {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 900)
        let anchor = CGRect(x: 80, y: 500, width: 340, height: 200)
        let frame = placement.frame(nextTo: anchor, size: size, visibleFrame: narrow, occupied: [anchor])
        #expect(frame.minX == anchor.minX + 28)
        #expect(frame.maxY == anchor.maxY - 28)
        #expect(narrow.contains(frame))
    }

    @Test func restoredFrameIsKeptWhileItsTopRowIsOnSomeScreen() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = CGRect(x: 2000, y: 700, width: 340, height: 200)
        let frame = placement.restoredFrame(saved: saved, screens: [screen, second], main: screen, handleHeight: 28)
        #expect(frame == saved)
    }

    @Test func restoredFrameMovesIntoTheMainScreenWhenItsScreenIsGone() {
        let saved = CGRect(x: 2000, y: 950, width: 340, height: 200)
        let frame = placement.restoredFrame(saved: saved, screens: [screen], main: screen, handleHeight: 28)
        #expect(screen.contains(frame))
        #expect(frame.size == saved.size)
        #expect(frame.maxX == 1416)
        #expect(frame.maxY == 876)
    }

    @Test func clampingKeepsTheTopEdgeWhenTheFrameIsTallerThanTheArea() {
        let tall = CGRect(x: 10, y: -500, width: 340, height: 1200)
        let frame = placement.clamped(tall, to: screen)
        #expect(frame.maxY == screen.maxY)
    }
}
