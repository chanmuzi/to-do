import CoreGraphics
import Testing
@testable import NotePanel

@Suite @MainActor struct TopRowLayoutTests {
    private let metrics = TopRowLayout.Metrics(
        height: 28, paddingLeading: 12, paddingTrailing: 6, gap: 6, iconButton: 20
    )

    private func layout(
        width: CGFloat = 340, space: CGFloat? = 13, title: CGFloat = 60, reminder: CGFloat? = 57,
        problem: Bool = false
    ) -> TopRowLayout {
        TopRowLayout(
            .init(width: width, spaceWidth: space, titleWidth: title, reminderWidth: reminder, showsProblem: problem),
            metrics: metrics
        )
    }

    @Test func elementsRunFromBothEdgesWithTheSpecGaps() {
        let frames = layout()
        #expect(frames.space?.minX == 12)
        #expect(frames.title.minX == 31)
        #expect(frames.title.width == 60)
        #expect(frames.pin == CGRect(x: 314, y: 4, width: 20, height: 20))
        #expect(frames.reminder?.maxX == frames.pin.minX - 6)
        #expect(frames.reminder?.width == 57)
        #expect(frames.add.maxX == (frames.reminder?.minX ?? 0) - 6)
        #expect(frames.more.maxX == frames.add.minX - 6)
        #expect(frames.search.maxX == frames.more.minX - 6)
    }

    @Test func absentSpaceAndReminderTakeNoSlot() {
        let frames = layout(space: nil, reminder: nil)
        #expect(frames.space == nil)
        #expect(frames.reminder == nil)
        #expect(frames.title.minX == 12)
        #expect(frames.add.maxX == frames.pin.minX - 6)
    }

    @Test func longTitleIsCutBeforeTheHoverIconSlots() {
        let frames = layout(title: 1000)
        #expect(frames.title.maxX == frames.search.minX - 6)
    }

    @Test func narrowNoteShrinksTheTitleFirst() {
        let wide = layout(width: 340, title: 1000, reminder: 93)
        let narrow = layout(width: 260, title: 1000, reminder: 93)
        #expect(narrow.title.width < wide.title.width)
        #expect(narrow.title.width > 0)
        #expect(narrow.pin.width == 20)
        #expect(narrow.reminder?.width == 93)
        #expect(narrow.pin.maxX == 254)
        #expect(narrow.search.minX >= narrow.title.maxX + 6)
    }

    @Test func titleNeverGoesNegativeWhenThereIsNoRoom() {
        #expect(layout(width: 120, title: 1000).title.width == 0)
    }

    @Test func problemIndicatorTakesASlotOnlyWhenShown() {
        let without = layout()
        let with = layout(problem: true)
        #expect(without.problem == nil)
        #expect(with.problem?.maxX == (with.reminder?.minX ?? 0) - 6)
        #expect(with.add.maxX == (with.problem?.minX ?? 0) - 6)
        #expect(with.pin == without.pin)
        #expect(with.reminder == without.reminder)
    }
}
