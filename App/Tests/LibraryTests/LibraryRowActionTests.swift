import AppKit
import Models
import Store
import SwiftUI
import Testing
@testable import Library

@Suite(.serialized) @MainActor struct LibraryRowActionTests {
    private let ui = LibraryInteractionTests()

    @Test func pinPersistsWithoutOpeningAndUnpinPreservesWindowState() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        let note = try f.notes.create(NoteDraft(title: "고정할 노트"))
        f.model.select(.all)
        var applied: [Bool] = []
        f.model.updateOpenWindowPin = { id, pin in
            #expect(id == note.id)
            applied.append(pin)
        }
        f.model.togglePin(note)
        #expect(f.model.sections.first?.header == .pinned)
        #expect(f.model.selectedNoteID == note.id)
        let location = StoreLocation.isolated(notesDirectory: f.root)
        let saved = try #require(WindowStateStore(location: location).state(for: note.id))
        #expect(saved.isPinned && !saved.isOpen)
        f.model.select(.floating)
        f.model.togglePin(note)
        let unpinned = try #require(WindowStateStore(location: location).state(for: note.id))
        var expected = saved
        expected.isPinned = false
        #expect(unpinned == expected)
        #expect(f.model.rows.isEmpty && f.model.selectedNoteID == nil)
        #expect(applied == [true, false])
    }

    private final class PointerWindow: NSWindow {
        var point = NSPoint.zero
        override var mouseLocationOutsideOfEventStream: NSPoint { point }
    }

    @Test func stationaryPointerTracksReplacementAndKeyboardFocusFollowsPinnedNote() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        let one = try f.notes.create(NoteDraft(title: "첫 노트"))
        let two = try f.notes.create(NoteDraft(title: "다음 노트"))
        _ = try f.notes.create(NoteDraft(title: "일반 노트"))
        f.model.select(.all)
        f.model.togglePin(one)
        f.model.togglePin(two)
        let window = PointerWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = LibraryHostingView(rootView: LibraryRootView(model: f.model))
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        ui.settle()
        let pinned = try #require(f.model.sections.first?.notes)
        #expect(pinned.count == 2)
        let first = try #require(root.libraryNoteRow(pinned[0].id))
        let originallyAt = first.convert(NSPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil)
        window.point = originallyAt
        first.synchronizeHover(at: originallyAt)
        #expect(!first.more.isHidden && first.pin.accessibilityLabel() == "고정 해제")
        let pointOnPin = NSPoint(x: first.pin.frame.midX, y: first.pin.frame.midY)
        #expect(first.hitTest(first.convert(pointOnPin, to: first.superview)) === first.pin)
        first.pin.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(f.model.theme.motion.duration + 0.05))
        root.layoutSubtreeIfNeeded()
        let replacement = try #require(root.libraryNoteRow(pinned[1].id))
        #expect(replacement.visibleRect.contains(replacement.convert(originallyAt, from: nil)))
        #expect(!replacement.more.isHidden)
        let moved = try #require(root.libraryNoteRow(pinned[0].id))
        #expect(f.model.index.windows[pinned[0].id]?.isPinned == false)
        #expect(moved.more.isHidden && moved.pin.isHidden)
        #expect(f.model.selectedNoteID == pinned[0].id)
        #expect(window.firstResponder === moved)
    }

    @Test func moreOpensBelowButtonAndOffersCommandsForTheCurrentSection() throws {
        let f = try LibraryInteractionTests.Fixture()
        defer { try? f.close() }
        try f.model.theme.setOverrides(f.model.theme.overrides.setting("motion.dur", to: "0s"))
        let note = try f.notes.create(NoteDraft(title: "긴 제목", body: "미리보기"))
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        f.model.select(.all)
        f.model.previewNoteHover = note.id
        ui.settle()
        let host = try #require(f.coordinator.window)
        let root = try #require(host.contentView)
        let row = try #require(root.libraryNoteRow(note.id))
        #expect(!row.more.isHidden && !row.pin.isHidden)
        #expect(row.pin.frame.midY == row.bounds.midY && row.pin.frame.width == 24)
        #expect(row.more.frame.minX - row.pin.frame.maxX == 2)
        #expect(row.pin.accessibilityLabel() == "고정" && row.more.accessibilityLabel() == "더 보기")
        let menu = try #require(row.noteMenu())
        #expect(menu.items.map(\.title) == ["열기", "보관함으로", "스페이스 옮기기"])
        row.more.performClick(nil)
        let visiblePopup = host.childWindows?.first { $0.isVisible }
        let popup = try #require(visiblePopup)
        let anchor = host.convertToScreen(row.more.convert(row.more.bounds, to: nil))
        #expect(abs(popup.frame.maxX - anchor.maxX) <= 1)
        #expect(abs(anchor.minY - popup.frame.maxY - f.model.theme.space(.sp1)) <= 1)
        #expect(f.model.selectedNoteID == note.id && f.routes.isEmpty)
        popup.close()
        menu.performActionForItem(at: 2)
        #expect(f.routes == [.openSpacePicker(note.id)])
        menu.performActionForItem(at: 1)
        f.model.select(.archived)
        ui.settle()
        let archive = try #require(root.libraryNoteRow(note.id))
        #expect(archive.pin.isHidden && !archive.more.isHidden)
        let archiveCommands = archive.noteMenu()?.items.map(\.title)
        #expect(archiveCommands == ["열기", "되돌리기", "스페이스 옮기기"])
        try f.notes.moveToTrash(note.id)
        f.model.refresh()
        f.model.select(.trash)
        ui.settle()
        let trash = try #require(root.libraryNoteRow(note.id))
        #expect(trash.pin.isHidden && !trash.more.isHidden)
        #expect(trash.noteMenu()?.items.map(\.title) == ["되돌리기"])
    }
}
