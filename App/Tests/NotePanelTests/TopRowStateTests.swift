import Foundation
import Models
import Testing
import Theme
@testable import NotePanel

@Suite @MainActor struct TopRowStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(title: String = "오늘 할 일", reminder: Date? = nil) -> Note {
        Note(id: NoteID(rawValue: "n"), title: title, reminder: reminder, created: now, modified: now)
    }

    private func state(
        _ note: Note,
        pinned: Bool = true,
        hovered: Bool = false,
        editing: Bool = false,
        problem: NoteProblem? = nil,
        options: NotePanelDisplayOptions = NotePanelDisplayOptions()
    ) -> TopRowState {
        TopRowState(
            note: note, isPinned: pinned, isHovered: hovered, isEditingTitle: editing,
            problem: problem, options: options, now: now, calendar: Calendar(identifier: .gregorian)
        )
    }

    @Test func restingRowIsDimAndHidesHoverControls() {
        let resting = state(note())
        #expect(resting.title == "오늘 할 일")
        #expect(!resting.isTitlePlaceholder)
        #expect(resting.titleColor == .text3)
        #expect(resting.hoverControlsAlpha == 0)
        #expect(resting.pin == .init(symbolName: "pin.fill", alpha: 1, color: .text3, isOn: true))
    }

    @Test func hoverDarkensTheTitleAndRevealsControls() {
        let hovered = state(note(), hovered: true)
        #expect(hovered.titleColor == .text)
        #expect(hovered.hoverControlsAlpha == 1)
        #expect(hovered.pin == .init(symbolName: "pin.fill", alpha: 1, color: .text2, isOn: true))
    }

    @Test func unpinnedPinAppearsOnlyOnHover() {
        #expect(state(note(), pinned: false).pin == .init(symbolName: "pin", alpha: 0, color: .text2, isOn: false))
        #expect(state(note(), pinned: false, hovered: true).pin.alpha == 1)
    }

    @Test func emptyTitleShowsThePlaceholder() {
        let untitled = state(note(title: ""))
        #expect(untitled.title == "제목 없음")
        #expect(untitled.isTitlePlaceholder)
        #expect(untitled.titleColor == .text3)
    }

    @Test func editingTheTitleDarkensItWithoutHover() {
        let editing = state(note(), editing: true)
        #expect(editing.titleColor == .text)
        #expect(editing.hoverControlsAlpha == 0)
    }

    @Test func reminderHasNoSlotWhenAbsent() {
        let bare = state(note())
        #expect(!bare.hasSchedules && bare.clockLabel == nil)
        #expect(!state(note(), hovered: true).hasSchedules)
        let reminded = state(note(reminder: now.addingTimeInterval(3600)))
        #expect(reminded.hasSchedules && reminded.clockColor == .text3)
    }

    @Test func clockDescribesUpcomingSchedulesThenCountsRemainingPastItems() {
        var sample = note()
        sample.schedules = [
            ScheduleItem(start: now.addingTimeInterval(7200)),
            ScheduleItem(start: now.addingTimeInterval(-60)),
            ScheduleItem(start: now.addingTimeInterval(3600)),
            ScheduleItem(start: now.addingTimeInterval(300), isCompleted: true),
            ScheduleItem(start: now.addingTimeInterval(400), isDeleted: true),
        ]
        let active = state(sample)
        let first = ReminderPresentation(reminder: now.addingTimeInterval(3600), now: now, options: .init(),
                                         calendar: Calendar(identifier: .gregorian))
        #expect(active.clockLabel == first.accessibilityLabel + " +1")
        sample.schedules.removeAll { $0.start > now }
        #expect(state(sample).clockLabel == "이 노트의 일정 1건")
        #expect(state(sample).clockColor == .text3)
        sample.schedules[0].isCompleted = true
        #expect(!state(sample).hasSchedules)
        sample.schedules[0].isCompleted = false
        sample.schedules[0].isDeleted = true
        #expect(!state(sample, hovered: true).hasSchedules)
    }

    @Test func imminentEventUsesWarnAndIncludesTheFullRangeInItsLabel() {
        var sample = note()
        sample.schedules = [ScheduleItem(start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400))]
        let active = state(sample, options: .init(reminder: .iconOnly))
        #expect(active.clockColor == .warn)
        #expect(active.clockLabel?.hasPrefix("일정 ") == true)
        #expect(active.clockLabel?.contains("~") == true)
        #expect(active.clockLabel?.hasSuffix("임박") == true)
    }

    @Test func syncFailureIsAnnouncedOnTheClockOrOnTheSeparateProblemButton() {
        var sample = note(reminder: now.addingTimeInterval(-60))
        sample.schedules[0].syncError = "동기화 오류"
        #expect(state(sample).clockLabel?.contains("연동 실패") == true)
        #expect(state(sample).problemLabel == nil)
        sample.schedules[0].isDeleted = true
        #expect(state(sample).problemLabel == "예정 연동 실패")
    }

    @Test func problemIsCarriedThrough() {
        #expect(state(note(), problem: .conflict).problem == .conflict)
        #expect(state(note()).problem == nil)
    }
}
