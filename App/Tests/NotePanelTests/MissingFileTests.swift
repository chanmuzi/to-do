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

    /// 새 노트로 저장하기 전에 편집기가 아직 알리지 않은 글(조합 중인 글자)을 받고, 접힘 같은 보기 상태를
    /// 새 노트로 옮긴다. 검토에서 나온 문제: 마지막에 친 글과 접힘이 새 노트에 오지 않았다.
    @Test func saveAsNewTakesTextNotYetReportedAndCarriesTheFolds() throws {
        var editors: [SpyBodyEditor] = []
        let coordinator = try fixture.makeCoordinator(makeBodyEditor: { _ in
            editors.append(SpyBodyEditor())
            return editors[editors.count - 1]
        })
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "지워질 노트", body: "+ 토글\n\t안"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        editors[0].type("+ 토글\n\t안쪽 글")
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()
        #expect(controller.problem == .fileMissing)
        // 편집기 어댑터가 창 상태에 적어 둔 접힘.
        let recorder = controller.environment.recorder
        var state = try #require(recorder.savedState(for: note.id))
        state.foldedLines = [0]
        state.foldedLineTexts = ["+ 토글"]
        recorder.restore(state, for: note.id)
        let frame = controller.panel.frame
        // 화면에만 있고 아직 알리지 않은 글.
        editors[0].compose("+ 토글\n\t안쪽 글 그리고 마지막에 친 글")

        controller.resolveProblem(.saveAsNewNote)

        #expect(editors[0].flushCount == 1)
        let newID = try #require(coordinator.openNoteIDs.first)
        #expect(coordinator.openNoteIDs.count == 1)
        #expect(newID != note.id)
        #expect(try fixture.notes.load(newID).body == "+ 토글\n\t안쪽 글 그리고 마지막에 친 글")
        #expect(editors.count == 2)
        #expect(editors[1].assignments == ["+ 토글\n\t안쪽 글 그리고 마지막에 친 글"])
        let carried = try #require(try fixture.windowState(for: newID))
        #expect(carried.foldedLines == [0])
        #expect(carried.foldedLineTexts == ["+ 토글"])
        #expect(carried.isOpen)
        #expect(carried.frame?.cgRect.minX == frame.minX)
        #expect(carried.frame?.cgRect.maxY == frame.maxY)
        #expect(try fixture.windowState(for: note.id) == nil)
    }
}


extension MissingFileTests {
    @Test func saveAsNewTransfersLinksBaselinesAndPendingDeletions() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var linked = ScheduleItem(start: Date(timeIntervalSince1970: 2_000_000_000), title: "연결 항목",
                                  link: .init(localID: "local", externalID: "external", kind: .reminder), syncedAt: Date())
        linked.syncBaseline = linked.value
        var deleted = linked
        deleted.id = "pending-delete"; deleted.isDeleted = true; deleted.syncError = "삭제 재시도"
        let legacy = ScheduleItem(id: "legacy-old", start: linked.start)
        let items = [linked, deleted, legacy]
        let note = try fixture.notes.create(NoteDraft(body: "원문", schedules: items))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try typeText(" 편집", into: controller)
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()
        controller.resolveProblem(.saveAsNewNote)
        let newID = try #require(coordinator.openNoteIDs.first)
        #expect(newID != note.id)
        let copied = try FileNoteStore(location: fixture.location).load(newID).schedules
        #expect(copied.count == items.count)
        for (old, new) in zip(items, copied) {
            #expect(new.id != old.id)
            var expected = old; expected.id = new.id
            #expect(new == expected)
        }
        #expect(copied[2].id.hasPrefix("legacy-"))
        #expect(!FileManager.default.fileExists(atPath: fixture.noteFile(note.id).path))
    }
}
