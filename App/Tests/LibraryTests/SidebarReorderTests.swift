import AppKit
import Models
import Store
import Testing
import Theme
@testable import Library

@MainActor @Suite(.serialized) struct SidebarReorderTests {
    @Test func peersMoveAtHalfHeightAndDropIsConfinedToTheOriginalSection() {
        let section = ReorderSection([.today, .all, .floating], stride: 30, extra: [.all: 30])
        let drag = SidebarReorder()
        drag.track(.today, in: section, translation: 29)
        #expect(drag.offset(.all, in: section) == 0)
        drag.track(.today, in: section, translation: 30)
        #expect(drag.offset(.all, in: section) == -30)
        drag.track(.today, in: section, translation: 1000)
        #expect(drag.offset(.today, in: section) == 90)
        drag.finish(in: ReorderSection([.space(.make())], stride: 30)) { _, _ in Issue.record("다른 구획으로 이동") }
        #expect(!drag.lifted(.today, in: section))
        drag.track(.all, in: section, translation: -80)
        drag.finish(in: section) { row, target in
            #expect(row == .all && target == .today)
        }
    }

    @Test func menuAndAccessibilityMovesPersistInExistingSpaceArray() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        let first = try f.model.spaces.create(name: "작업실")
        let second = try f.model.spaces.create(name: "일상")
        let section = f.model.spaceSection
        let actions = ReorderActions(.space(first.id), section: section, move: f.model.moveSidebar)
        #expect(!actions.available(-1) && actions.available(1))
        actions.perform(-1)
        f.model.moveSidebar(.space(first.id), to: .all)
        #expect(f.model.spaceList == [first, second])
        actions.perform(1)
        #expect(f.model.spaceList == [second, first])
        #expect(try SpaceStore(location: .isolated(notesDirectory: f.root)).spaces == [second, first])
    }

    @Test func clickSelectsAndPanReordersWithoutSelectingOrActivating() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        let events = LibraryInteractionTests()
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        events.settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let row = try #require(events.descendants(root).first { $0.accessibilityLabel() == "고정됨 호버" })
        let start = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        try events.click(window, at: start)
        #expect(f.model.selection == .floating)
        f.model.select(.today)
        try dragOneRow(in: window, from: start, theme: f.model.theme)
        #expect(f.model.settings.visibleViews == [.today, .all, .floating])
        #expect(f.model.selection == .today && !window.isKeyWindow)
    }

    @Test func expandedSpaceCanMoveFromItsNameWithoutSelectingOrRenaming() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        let first = try f.model.spaces.create(name: "작업실")
        let second = try f.model.spaces.create(name: "일상")
        var draft = NoteDraft(title: "날짜가 있는 노트")
        draft.spaceID = first.id
        _ = try f.notes.create(draft)
        f.model.expanded.insert(first.id)
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        let events = LibraryInteractionTests()
        events.settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let row = try #require(events.descendants(root).first { $0.accessibilityLabel() == "작업실 호버" })
        let start = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        try dragOneRow(in: window, from: start, theme: f.model.theme)
        #expect(f.model.spaceList == [second, first])
        #expect(f.model.expanded.contains(first.id) && !f.model.editingSpace)
        #expect(f.model.selection == .today && !window.isKeyWindow)
    }

    private func dragOneRow(in window: NSWindow, from start: CGPoint, theme: Theme) throws {
        let stride = theme.component(.rowHeight) + theme.component(.librarySidebarRowGap)
        for (type, dy) in [(NSEvent.EventType.leftMouseDown, CGFloat.zero), (.leftMouseDragged, stride / 3),
                            (.leftMouseDragged, stride), (.leftMouseUp, stride)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: .init(x: start.x, y: start.y - dy),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
            LibraryInteractionTests().settle()
        }
    }
}
