import AppKit
import Foundation
import Models
import Store
import Testing
@_spi(Verification) @testable import NotePanel

/// 아무것도 적지 않은 노트(제목과 본문이 비었거나 공백뿐, 리마인더 없음)는 창을 닫을 때와 앱을 끝낼 때
/// 휴지통을 거치지 않고 지운다(D-040). 무엇이든 적힌 노트는 지우지 않는다.
@Suite @MainActor struct BlankNoteTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func exists(_ id: NoteID) -> Bool {
        FileManager.default.fileExists(atPath: fixture.noteFile(id).path)
    }

    @Test func closingABlankNoteDeletesItAndItsWindowState() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let id = try coordinator.createNote()
        coordinator.setColor(PaletteID(rawValue: "tint-2"), for: id)
        coordinator.closeWindow(id)
        #expect(!exists(id))
        #expect(!FileManager.default.fileExists(atPath: fixture.trashFile(id).path))
        #expect(try fixture.windowState(for: id) == nil)
        #expect(!coordinator.canUndoTrash)
    }

    @Test func closingANoteWithAnythingWrittenKeepsIt() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let drafts = [
            NoteDraft(title: "제목만"), NoteDraft(body: "본문만"), NoteDraft(body: "[ ]"),
            NoteDraft(reminder: Date().addingTimeInterval(3600)),
        ]
        for draft in drafts {
            let note = try fixture.notes.create(draft)
            try coordinator.open(note.id, focus: false)
            coordinator.closeWindow(note.id)
            #expect(exists(note.id), "\(draft)")
        }
    }

    /// 창을 닫기 직전에 편집기가 아직 알리지 않은 글도 적은 것으로 친다.
    @Test func textTypedJustBeforeClosingKeepsTheNote() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let id = try coordinator.createNote()
        let controller = try #require(coordinator.controllers[id])
        controller.editor.focus()
        let textView = try #require(controller.panel.firstResponder as? NSTextView)
        textView.insertText("방금 친 글", replacementRange: textView.selectedRange())
        coordinator.closeWindow(id)
        #expect(exists(id))
        #expect(try fixture.notes.load(id).body == "방금 친 글")
    }

    /// 앱을 끝낼 때: 떠 있는 빈 노트만 지운다.
    @Test func quittingDeletesOnlyBlankOpenNotes() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let blank = try coordinator.createNote()
        let written = try fixture.notes.create(NoteDraft(title: "남길 노트"))
        try coordinator.open(written.id, focus: false)
        let closedBlank = try fixture.notes.create(NoteDraft())

        #expect(coordinator.deleteBlankNotes() == [blank])
        #expect(!exists(blank))
        #expect(exists(written.id))
        // 떠 있지 않은 노트는 건드리지 않는다.
        #expect(exists(closedBlank.id))
    }

    /// 휴지통으로 보낸 빈 노트는 지우지 않고 휴지통에 남는다(되돌릴 수 있다).
    @Test func trashingABlankNoteStillGoesToTheTrash() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let id = try coordinator.createNote()
        coordinator.moveToTrash(id)
        #expect(FileManager.default.fileExists(atPath: fixture.trashFile(id).path))
        #expect(coordinator.canUndoTrash)
    }
}
