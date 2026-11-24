import AppKit
import Models
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct TopRowLayoutTests {
    private let metrics: TopRowLayout.Metrics
    init() throws {
        let theme = try Theme.bundled()
        metrics = .init(height: theme.shape(.chromeHeight), paddingLeading: theme.space(.sp3),
                        paddingTrailing: theme.component(.noteTopPaddingEnd), gap: theme.component(.chromeGap),
                        iconButton: theme.component(.noteTopButtonSize), dividerWidth: theme.shape(.borderWidth),
                        buttonGap: theme.component(.noteTopButtonGap))
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

    @Test func hitAndReleaseMeetBetweenVisibleButtonsIncludingTheDivider() throws {
        let theme = try Theme.bundled()
        let row = TopRowView(style: PanelStyle(theme: theme))
        let panel = NotePanelWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: metrics.height))
        panel.allowsKey = false
        panel.contentView = row
        let now = Date()
        let note = Note(id: NoteID(rawValue: "top"), title: "노트", reminder: now.addingTimeInterval(-86400), created: now, modified: now)
        row.apply(TopRowState(note: note, isPinned: true, isHovered: true, isEditingTitle: false,
                              problem: nil, options: .init(), now: now, calendar: .current), animated: false)
        let buttons = row.subviews.compactMap { $0 as? IconButton }
            .filter { !$0.isHidden && $0.alphaValue > 0 }.sorted { $0.frame.minX < $1.frame.minX }
        #expect(buttons.count == 5)
        for (left, right) in zip(buttons, buttons.dropFirst()) {
            let midpoint = (left.frame.maxX + right.frame.minX) / 2
            for x in stride(from: left.frame.maxX, to: right.frame.minX, by: 0.25) {
                let point = row.convert(CGPoint(x: x, y: left.frame.midY), to: nil)
                let target = x < midpoint ? left : right
                #expect(panel.button(at: point) === target)
                #expect(target.acceptsRelease(at: point))
                #expect(!(target === left ? right : left).acceptsRelease(at: point))
            }
        }
        let dragPoint = row.convert(CGPoint(x: 90, y: metrics.height / 2), to: nil)
        #expect(panel.button(at: dragPoint) == nil)
    }

    @Test func restingFaceAndPinHaveDistinctSlots() {
        for allows in [true, false] {
            for pinned in [true, false] {
                let frames = TopRowLayout(.init(width: 260, titleWidth: 300, reminderWidth: 80,
                    showsControls: false, allowsAgent: allows, hasAgentActivity: true,
                    isPinned: pinned, showsProblem: false), metrics: metrics)
                #expect((frames.agent != .zero) == allows)
                #expect((frames.pin != .zero) == pinned)
                if allows && pinned { #expect(frames.agent.maxX <= frames.pin.minX) }
                #expect(!frames.title.intersects(frames.agent))
            }
        }
    }

    @Test func clockReplacesAbsentChip() {
        let frames = layout(reminder: nil)
        #expect(frames.reminder == nil)
        #expect(frames.title.minX == metrics.paddingLeading)
        #expect(frames.agent.maxX + metrics.buttonGap == frames.clock.minX)
        #expect(frames.clock.maxX + metrics.buttonGap == frames.pin.minX)
    }

    @Test func restingPinReservesTheTrailingSlotAndTheChipGap() {
        for pinned in [false, true] {
            for chip: CGFloat? in [nil, 57] {
                let frames = TopRowLayout(.init(width: 340, titleWidth: 1000, reminderWidth: chip,
                                                showsControls: false, isPinned: pinned, showsProblem: false),
                                          metrics: metrics)
                let right = 340 - metrics.paddingTrailing
                #expect(frames.agent == .zero && frames.more == .zero && frames.close == .zero && frames.divider == .zero && frames.clock == .zero)
                if pinned {
                    #expect(frames.pin.maxX == right && frames.pin.width == metrics.iconButton)
                } else {
                    #expect(frames.pin == .zero)
                }
                let contentRight = pinned ? frames.pin.minX : right
                if let reminder = frames.reminder {
                    #expect(reminder.maxX == contentRight - (pinned ? metrics.gap : 0))
                    #expect(frames.title.maxX == reminder.minX - metrics.gap)
                } else {
                    #expect(frames.title.maxX == contentRight - metrics.gap)
                }
            }
        }
    }

    @Test func longTitleIsCutBeforeTheHoverIconSlots() {
        let frames = layout(title: 1000)
        #expect(frames.title.maxX == frames.agent.minX - metrics.gap)
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
        #expect((with.problem?.maxX ?? 0) + metrics.buttonGap == with.agent.minX)
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
