import AppKit
import Models
import Store
import Testing
@testable import NotePanel

/// 다른 프로그램이 노트 파일을 지웠을 때(Finder, 동기화 도구, `git checkout`).
/// 쓰지 못한 글이 있는 창은 닫지 않고 새 노트로 저장할지 버릴지 고르게 한다.
@Suite @MainActor struct MissingFileTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func typeText(_ text: String, into controller: NoteWindowController) throws {
        let textView = try #require(controller.editor.view as? NSTextView)
        textView.insertText(text, replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
    }

    /// 글을 쓴 뒤 파일이 지워진 창.
    private func openEditedNoteWhoseFileVanished() throws -> (NotePanelCoordinator, NoteWindowController) {
        let coordinator = try fixture.makeCoordinator()
        let note = try fixture.notes.create(NoteDraft(
            title: "지워질 노트", body: "처음", colorID: PaletteID(rawValue: "tint-4")
        ))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try typeText(" 그리고 쓰지 못한 글", into: controller)
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()
        return (coordinator, controller)
    }

    @Test func externalDeleteKeepsAWindowThatHoldsUnwrittenText() throws {
        let (coordinator, controller) = try openEditedNoteWhoseFileVanished()
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        #expect(coordinator.openNoteIDs == [id])
        #expect(controller.problem == .fileMissing)
        #expect(controller.editor.text == "처음 그리고 쓰지 못한 글")
        #expect(coordinator.snapshot(of: id)?.problem != nil)
        // 닫으려 해도, 휴지통으로 보내려 해도 글이 남아 있는 창은 닫히지 않는다.
        coordinator.closeWindow(id)
        coordinator.moveToTrash(id)
        #expect(coordinator.openNoteIDs == [id])
        #expect(controller.problem == .fileMissing)
        // 더 쳐도 표시는 그대로이고 글은 남는다.
        try typeText("!", into: controller)
        #expect(controller.problem == .fileMissing)
        #expect(controller.latestNote.body == "처음 그리고 쓰지 못한 글!")
    }

    @Test func missingFileMenuOffersSaveAsNewAndDiscard() throws {
        defer { fixture.cleanUp() }
        var chosen: [ProblemMenuAction] = []
        let menu = NoteMenuBuilder(style: PanelStyle(theme: fixture.theme))
            .problemMenu(for: .fileMissing) { chosen.append($0) }

        #expect(menu.items.map(\.title) == ["노트 파일이 없어졌습니다", "새 노트로 저장", "버리기"])
        #expect(!menu.items[0].isEnabled)
        for item in menu.items.dropFirst() {
            (item.target as? MenuActionTarget)?.fire()
        }
        #expect(chosen == [.saveAsNewNote, .discard])
    }

    @Test func saveAsNewMovesTheTextToANewNoteInTheSamePlace() throws {
        let (coordinator, controller) = try openEditedNoteWhoseFileVanished()
        defer { fixture.cleanUp(coordinator) }
        let oldID = controller.noteID
        coordinator.setPinned(false, for: oldID)
        let oldFrame = controller.panel.frame

        controller.resolveProblem(.saveAsNewNote)

        let newID = try #require(coordinator.openNoteIDs.first)
        #expect(coordinator.openNoteIDs.count == 1)
        #expect(newID != oldID)
        let saved = try FileNoteStore(location: fixture.location).load(newID)
        #expect(saved.title == "지워질 노트")
        #expect(saved.body == "처음 그리고 쓰지 못한 글")
        #expect(saved.colorID == PaletteID(rawValue: "tint-4"))
        let window = try #require(coordinator.snapshot(of: newID))
        #expect(window.frame == oldFrame)
        #expect(!window.isPinned)
        #expect(window.problem == nil)
        #expect(coordinator.controllers[newID]?.editor.text == "처음 그리고 쓰지 못한 글")
        // 옛 노트의 것은 남지 않는다: 창 상태, 저장소가 들고 있던 변경.
        #expect(try fixture.windowState(for: oldID) == nil)
        #expect(!fixture.notes.hasPendingChanges(oldID))
        try fixture.notes.flushPendingSaves()
        #expect(!FileManager.default.fileExists(atPath: fixture.noteFile(oldID).path))
    }

    @Test func discardDropsTheTextAndClosesTheWindow() throws {
        let (coordinator, controller) = try openEditedNoteWhoseFileVanished()
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        controller.resolveProblem(.discard)

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(try fixture.windowState(for: id) == nil)
        #expect(!fixture.notes.hasPendingChanges(id))
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.notes.list().notes.isEmpty)
    }

    /// 파일이 지워진 것을 아직 모르는 채로 글을 쳤다. 저장소가 받지 못한 글도 창이 들고 있다가 새 노트로 옮긴다.
    @Test func textTypedAfterTheFileVanishedIsKeptAndCanBeSavedAsNew() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "모르고 친 글", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))

        try typeText(" 뒤에 친 글", into: controller)
        controller.root.topRow.actions.titleChanged("고친 제목")

        #expect(coordinator.openNoteIDs == [note.id])
        #expect(controller.problem == .fileMissing)
        coordinator.closeWindow(note.id)
        #expect(coordinator.openNoteIDs == [note.id])

        controller.resolveProblem(.saveAsNewNote)
        let newID = try #require(coordinator.openNoteIDs.first)
        let saved = try fixture.notes.load(newID)
        #expect(saved.title == "고친 제목")
        #expect(saved.body == "처음 뒤에 친 글")
    }

    /// 동기화 도구가 지웠다 같은 내용으로 다시 만든 경우: 남아 있던 변경을 쓰고 표시를 거둔다.
    @Test func fileComingBackUnchangedLetsThePendingEditBeWritten() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "돌아올 노트", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let original = try Data(contentsOf: fixture.noteFile(note.id))
        try typeText(" 고침", into: controller)
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()
        #expect(controller.problem == .fileMissing)

        try original.write(to: fixture.noteFile(note.id))
        try fixture.notes.refresh()

        #expect(controller.problem == nil)
        #expect(try String(contentsOf: fixture.noteFile(note.id), encoding: .utf8).hasSuffix("처음 고침"))
    }

    /// 다시 생긴 파일의 내용이 다르면 덮어쓰지 않고 충돌로 넘어간다.
    @Test func fileComingBackChangedBecomesAConflict() throws {
        let (coordinator, controller) = try openEditedNoteWhoseFileVanished()
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        try Data("다른 프로그램이 새로 만든 내용".utf8).write(to: fixture.noteFile(id))
        try fixture.notes.refresh()

        #expect(controller.problem == .conflict)
        #expect(controller.editor.text == "처음 그리고 쓰지 못한 글")
        #expect(try String(contentsOf: fixture.noteFile(id), encoding: .utf8) == "다른 프로그램이 새로 만든 내용")
    }
}
