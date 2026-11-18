import CoreGraphics
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct TopRowLayoutTests {
    private let metrics: TopRowLayout.Metrics
    init() throws {
        let theme = try Theme.bundled()
        metrics = .init(height: theme.shape(.chromeHeight), paddingLeading: theme.space(.sp3),
                        paddingTrailing: theme.component(.chromePaddingEnd), gap: theme.component(.chromeGap),
                        iconButton: theme.component(.iconButton), dividerWidth: theme.shape(.borderWidth),
                        buttonGap: theme.component(.iconButtonGap))
    }

    private func layout(
        width: CGFloat = 340, title: CGFloat = 60, reminder: CGFloat? = 57,
        problem: Bool = false
    ) -> TopRowLayout {
        TopRowLayout(
            .init(width: width, titleWidth: title, reminderWidth: reminder, showsProblem: problem),
            metrics: metrics
        )
    }

    @Test func elementsRunFromBothEdgesWithTheSpecGaps() {
        let frames = layout()
        #expect(frames.title.minX == metrics.paddingLeading)
        #expect(frames.title.width == 60)
        #expect(frames.close.maxX == 340 - metrics.paddingTrailing)
        #expect(frames.close.height == metrics.iconButton)
        #expect(frames.reminder?.midY == frames.close.midY)
        #expect(frames.reminder?.maxX == frames.pin.minX - metrics.gap)
        #expect(frames.reminder?.width == 57)
        #expect(frames.pin.maxX + metrics.buttonGap == frames.more.minX)
    }

    @Test func clockReplacesAbsentChip() {
        let frames = layout(reminder: nil)
        #expect(frames.reminder == nil)
        #expect(frames.title.minX == metrics.paddingLeading)
        #expect(frames.clock.maxX + metrics.buttonGap == frames.pin.minX)
    }

    @Test func longTitleIsCutBeforeTheHoverIconSlots() {
        let frames = layout(title: 1000)
        #expect(frames.title.maxX == (frames.reminder?.minX ?? 0) - metrics.gap)
    }

    @Test func narrowNoteShrinksTheTitleFirst() {
        let wide = layout(width: 340, title: 1000, reminder: 93)
        let narrow = layout(width: 260, title: 1000, reminder: 93)
        #expect(narrow.title.width < wide.title.width)
        #expect(narrow.title.width > 0)
        #expect(narrow.pin.width == metrics.iconButton)
        #expect(narrow.reminder?.width == 93)
        #expect(narrow.close.maxX == 260 - metrics.paddingTrailing)
        #expect(narrow.more.minX >= narrow.title.maxX + metrics.gap)
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
        #expect((with.problem?.maxX ?? 0) + metrics.buttonGap == with.reminder?.minX)
        #expect(with.problem?.width == metrics.iconButton)
        #expect(with.more == without.more)
        #expect(with.pin == without.pin)
        #expect(with.reminder == without.reminder)
        #expect(with.title.minX == without.title.minX)
        #expect(with.title.maxX == (with.problem?.minX ?? 0) - metrics.gap)
        // 짧은 제목은 그대로다.
        #expect(layout(problem: true).title == layout().title)
    }
}
