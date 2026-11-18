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
        #expect(resting.pin == .init(symbolName: "pin.fill", alpha: 0, color: .text3, isOn: true))
    }

    @Test func hoverDarkensTheTitleAndRevealsControls() {
        let hovered = state(note(), hovered: true)
        #expect(hovered.titleColor == .text)
        #expect(hovered.hoverControlsAlpha == 1)
        #expect(hovered.pin.color == .text2)
    }

    @Test func unpinnedPinKeepsItsSlotAndAppearsOnlyOnHover() {
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
        #expect(bare.reminder == nil)
        let reminded = state(note(reminder: now.addingTimeInterval(3600)))
        #expect(reminded.reminder?.status == .scheduled)
    }

    @Test func chipCountsOnlyPendingSchedulesAndExpires() {
        var sample = note()
        sample.schedules = [
            ScheduleItem(start: now.addingTimeInterval(7200)),
            ScheduleItem(start: now.addingTimeInterval(-60)),
            ScheduleItem(start: now.addingTimeInterval(3600)),
            ScheduleItem(start: now.addingTimeInterval(300), isCompleted: true),
            ScheduleItem(start: now.addingTimeInterval(400), isDeleted: true),
        ]
        let active = state(sample)
        #expect(active.additionalSchedules == 1)
        #expect(active.reminder == state(note(reminder: now.addingTimeInterval(3600))).reminder)
        sample.schedules.removeAll { $0.start > now }
        #expect(state(sample).reminder == nil)
    }

    @Test func problemIsCarriedThrough() {
        #expect(state(note(), problem: .conflict).problem == .conflict)
        #expect(state(note()).problem == nil)
    }
}
