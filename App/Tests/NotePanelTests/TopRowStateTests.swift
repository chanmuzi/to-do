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
        space: Space? = nil,
        pinned: Bool = true,
        hovered: Bool = false,
        editing: Bool = false,
        problem: NoteProblem? = nil,
        options: NotePanelDisplayOptions = NotePanelDisplayOptions()
    ) -> TopRowState {
        TopRowState(
            note: note, space: space, isPinned: pinned, isHovered: hovered, isEditingTitle: editing,
            problem: problem, options: options, now: now, calendar: Calendar(identifier: .gregorian)
        )
    }

    private let work = Space(
        id: SpaceID(rawValue: "work"), name: "회사", icon: .symbol(name: "briefcase", colorID: nil)
    )

    @Test func restingRowIsDimAndHidesHoverControls() {
        let resting = state(note(), space: work)
        #expect(resting.title == "오늘 할 일")
        #expect(!resting.isTitlePlaceholder)
        #expect(resting.titleColor == .text3)
        #expect(resting.spaceColor == .text3)
        #expect(resting.hoverControlsAlpha == 0)
        #expect(resting.pin == .init(symbolName: "pin.fill", alpha: 1, color: .text3, isOn: true))
    }

    @Test func hoverDarkensTheTitleAndRevealsControls() {
        let hovered = state(note(), space: work, hovered: true)
        #expect(hovered.titleColor == .text)
        #expect(hovered.spaceColor == .text2)
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

    @Test func spaceAndReminderHaveNoSlotWhenAbsent() {
        let bare = state(note())
        #expect(bare.space == nil)
        #expect(bare.reminder == nil)
        let reminded = state(note(reminder: now.addingTimeInterval(3600)))
        #expect(reminded.reminder?.status == .scheduled)
    }

    @Test func spaceDisplayModes() {
        typealias Badge = TopRowState.SpaceBadge
        #expect(state(note(), space: work).space == Badge(symbolName: "briefcase"))
        #expect(state(note(), space: work, options: .init(space: .iconAndName)).space
            == Badge(symbolName: "briefcase", name: "회사"))
        #expect(state(note(), space: work, options: .init(space: .name)).space == Badge(name: "회사"))
        let emoji = Space(id: SpaceID(rawValue: "home"), name: "개인", icon: .emoji("🏠"))
        #expect(state(note(), space: emoji).space == Badge(emoji: "🏠"))
    }

    @Test func imageIconsFallBackToTheSpaceName() {
        let pixel = Space(id: SpaceID(rawValue: "dev"), name: "개발", icon: .image("terminal"))
        #expect(state(note(), space: pixel).space == TopRowState.SpaceBadge(name: "개발"))
    }

    @Test func problemIsCarriedThrough() {
        #expect(state(note(), problem: .conflict).problem == .conflict)
        #expect(state(note()).problem == nil)
    }
}
