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
        // 나란히 놓인 아이콘 버튼은 `icon-btn-gap`(0)만큼: hover 상자가 맞닿는다.
        #expect(frames.more.maxX == frames.add.minX)
    }

    @Test func absentSpaceAndReminderTakeNoSlot() {
        let frames = layout(space: nil, reminder: nil)
        #expect(frames.space == nil)
        #expect(frames.reminder == nil)
        #expect(frames.title.minX == 12)
        #expect(frames.add.maxX == frames.pin.minX)
    }

    @Test func longTitleIsCutBeforeTheHoverIconSlots() {
        let frames = layout(title: 1000)
        #expect(frames.title.maxX == frames.more.minX - 6)
    }

    @Test func narrowNoteShrinksTheTitleFirst() {
        let wide = layout(width: 340, title: 1000, reminder: 93)
        let narrow = layout(width: 260, title: 1000, reminder: 93)
        #expect(narrow.title.width < wide.title.width)
        #expect(narrow.title.width > 0)
        #expect(narrow.pin.width == 20)
        #expect(narrow.reminder?.width == 93)
        #expect(narrow.pin.maxX == 254)
        #expect(narrow.more.minX >= narrow.title.maxX + 6)
    }

    @Test func titleNeverGoesNegativeWhenThereIsNoRoom() {
        #expect(layout(width: 120, title: 1000).title.width == 0)
    }

    /// 저장 문제 표시는 호버 아이콘의 왼쪽에 놓인다. 나타나도 자리를 미리 차지하는 것들은 움직이지 않고
    /// 긴 제목이 잘리는 자리만 달라진다(규칙 7).
    @Test func problemIndicatorTakesASlotOnlyWhenShownWithoutMovingReservedSlots() {
        let without = layout(title: 1000)
        let with = layout(title: 1000, problem: true)
        #expect(without.problem == nil)
        #expect(with.problem?.maxX == with.more.minX)
        #expect(with.problem?.width == 20)
        #expect(with.more == without.more)
        #expect(with.add == without.add)
        #expect(with.pin == without.pin)
        #expect(with.reminder == without.reminder)
        #expect(with.title.minX == without.title.minX)
        #expect(with.title.maxX == (with.problem?.minX ?? 0) - 6)
        // 짧은 제목은 그대로다.
        #expect(layout(problem: true).title == layout().title)
    }
}
