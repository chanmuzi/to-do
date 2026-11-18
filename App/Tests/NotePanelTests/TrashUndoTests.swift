import AppKit
import Models
import Store
import Testing
@_spi(Verification) @testable import NotePanel

/// 휴지통으로 보낸 바로 뒤의 되돌리기(spec 5.3)와, App이 다른 화면을 붙일 때 쓰는 창 조회.
@Suite @MainActor struct TrashUndoTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    @Test func undoRightAfterTrashRestoresTheNoteAndItsWindow() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "되돌릴 노트", body: "+ 토글\n\t안쪽"))
        try coordinator.open(note.id, focus: false)
        coordinator.setPinned(false, for: note.id)
        let panel = try #require(coordinator.window(for: note.id))
        panel.setFrameOrigin(NSPoint(x: 140, y: 260))
        coordinator.controllers[note.id]?.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        let frame = panel.frame
        #expect(coordinator.canUndoTrash == false)

        coordinator.moveToTrash(note.id)
        #expect(coordinator.canUndoTrash)
        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(try fixture.windowState(for: note.id) == nil)

        #expect(try coordinator.undoTrash() == note.id)

        #expect(!coordinator.canUndoTrash)
        #expect(FileManager.default.fileExists(atPath: fixture.noteFile(note.id).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.trashFile(note.id).path))
        let restored = try #require(coordinator.snapshot(of: note.id))
        #expect(restored.frame == frame)
        #expect(!restored.isPinned)
        #expect(restored.isVisible)
        #expect(try fixture.notes.load(note.id).body == "+ 토글\n\t안쪽")
        #expect(try fixture.windowState(for: note.id)?.isOpen == true)
        // 한 번 더 부르면 되돌릴 것이 없다.
        #expect(try coordinator.undoTrash() == nil)
    }

    /// 창 상태에 함께 적힌 접힘(편집기 어댑터의 것)도 되돌리기로 돌아온다.
    @Test func undoBringsBackFoldsStoredInTheWindowState() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "+ 토글\n\t안쪽"))
        try coordinator.open(note.id, focus: false)
        let recorder = try #require(coordinator.controllers[note.id]).environment.recorder
        var state = try #require(recorder.savedState(for: note.id))
        state.foldedLines = [0]
        recorder.restore(state, for: note.id)

        coordinator.moveToTrash(note.id)
        try coordinator.undoTrash()

        #expect(try fixture.windowState(for: note.id)?.foldedLines == [0])
    }

    /// "바로 뒤"만이다: 그 뒤에 다른 노트를 고치거나 새 노트를 만들면 되돌리지 않는다.
    @Test func editingOrCreatingAfterTrashEndsTheUndo() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let kept = try fixture.notes.create(NoteDraft(title: "남는 노트"))
        try coordinator.open(kept.id, focus: false)
        let textView = try #require(coordinator.controllers[kept.id]?.editor.view as? NSTextView)

        let first = try fixture.notes.create(NoteDraft(title: "하나"))
        try coordinator.open(first.id, focus: false)
        coordinator.moveToTrash(first.id)
        textView.insertText("다른 노트를 고침", replacementRange: NSRange(location: 0, length: 0))
        #expect(!coordinator.canUndoTrash)
        #expect(try coordinator.undoTrash() == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.trashFile(first.id).path))

        let second = try fixture.notes.create(NoteDraft(title: "둘"))
        try coordinator.open(second.id, focus: false)
        coordinator.moveToTrash(second.id)
        #expect(coordinator.canUndoTrash)
        try coordinator.createNote()
        #expect(!coordinator.canUndoTrash)
    }

    /// 휴지통으로 보내지 못했으면(충돌) 되돌릴 것도 없다.
    @Test func failedTrashLeavesNothingToUndo() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "처음"))
        try coordinator.open(note.id, focus: false)
        let textView = try #require(coordinator.controllers[note.id]?.editor.view as? NSTextView)
        textView.insertText("내 글", replacementRange: NSRange(location: 0, length: 0))
        try fixture.appendOutside("\n밖에서 쓴 줄", to: note.id)

        coordinator.moveToTrash(note.id)

        #expect(coordinator.openNoteIDs == [note.id])
        #expect(!coordinator.canUndoTrash)
    }

    // MARK: - 창 조회

    @Test func windowAndFrontmostNoteAreAvailableForAnchoringOtherScreens() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        #expect(coordinator.frontmostNoteID == nil)
        let first = try fixture.notes.create(NoteDraft(title: "뒤"))
        let second = try fixture.notes.create(NoteDraft(title: "앞"))
        try coordinator.open(first.id, focus: false)
        try coordinator.open(second.id, focus: false)

        #expect(coordinator.window(for: first.id) === coordinator.controllers[first.id]?.panel)
        #expect(coordinator.window(for: NoteID(rawValue: "없는 노트")) == nil)
        // 키 창이 없으면 가장 앞에 겹친 노트다.
        #expect(coordinator.frontmostNoteID == second.id)
        try coordinator.open(first.id, focus: false)
        #expect(coordinator.frontmostNoteID == first.id)
        coordinator.toggleAllHidden()
        #expect(coordinator.frontmostNoteID == nil)

        coordinator.closeWindow(first.id)
        #expect(coordinator.window(for: first.id) == nil)
    }

    /// 확인용: 끄면 노트 창이 키 창이 되지 않는다(자동 확인이 사용자의 입력을 가져오지 않게).
    @Test func keyWindowsCanBeTurnedOffForVerificationRuns() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let first = try fixture.notes.create(NoteDraft(title: "먼저 뜬 노트"))
        try coordinator.open(first.id, focus: false)
        #expect(coordinator.allowsKeyWindows == false)
        let panel = try #require(coordinator.controllers[first.id]).panel
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        coordinator.allowsKeyWindows = true
        #expect(panel.canBecomeKey)

        coordinator.allowsKeyWindows = false
        let second = try coordinator.createNote()

        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(coordinator.controllers[second]?.panel.allowsKey == false)
        #expect(coordinator.keyNoteID == nil)
    }

    /// 노트 창은 보통 앱 창처럼 누르면 앱을 앞으로 가져오는 창이다(D-025). 키 창은 앱이 앞에 있을 때만 키 입력을
    /// 받으므로 언제 키 창이 되는지를 막지 않는다(손쉬운 사용 도구의 포커스 요청도 그대로 받는다).
    /// 앱이 뒤로 가도 숨지 않고, 모든 Spaces와 전체 화면 앱 위에 보인다.
    @Test func noteWindowIsAnActivatingWindowThatStaysVisible() {
        let panel = NotePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 100))
        defer { panel.close() }
        panel.orderFront(nil)
        #expect(!panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.setPinned(true)
        #expect(panel.level == .floating)
        panel.setPinned(false)
        #expect(panel.level == .normal)
        panel.allowsKey = false
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    /// 창을 띄우기만 해서는(되살리기, 앞으로 가져오기) 키 창을 시키지 않는다. 커서를 두라고 할 때만 시킨다.
    @Test func openingWithoutFocusNeverAsksForKey() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        coordinator.allowsKeyWindows = true
        let note = try fixture.notes.create(NoteDraft(title: "되살린 노트"))
        try coordinator.open(note.id, focus: false)
        let panel = try #require(coordinator.controllers[note.id]).panel

        #expect(panel.keyRequestCount == 0)
        #expect(!panel.isKeyWindow)
        #expect(coordinator.keyNoteID == nil)
        coordinator.allowsKeyWindows = false
    }

    @Test func nextNoteCyclesInOpeningOrder() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        #expect(coordinator.focusNextNote() == nil)
        let ids = try ["가", "나", "다"].map { try fixture.notes.create(NoteDraft(title: $0)).id }
        try ids.forEach { try coordinator.open($0, focus: false) }

        // 맨 앞은 마지막에 띄운 "다"이다. 다음은 처음으로 돌아간다.
        #expect(coordinator.focusNextNote() == ids[0])
        #expect(coordinator.frontmostNoteID == ids[0])
        #expect(coordinator.focusNextNote() == ids[1])
        #expect(coordinator.focusNextNote() == ids[2])
    }

    @Test func titleEditingCanBeStartedFromOutside() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        coordinator.beginTitleEditing(for: note.id)

        #expect(controller.root.topRow.isEditingTitle)
    }

    /// 창을 띄우는 배치 도중에 알게 된 내용 높이로 창이 커져도 본문 영역이 창을 따라간다.
    @Test func bodyAreaFillsTheWindowAfterTheHeightIsLearnedDuringLayout() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "하나\n둘\n셋\n넷\n다섯"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        controller.root.layoutSubtreeIfNeeded()

        let scrollView = try #require(controller.editor.view.enclosingScrollView)
        #expect(scrollView.frame.height == controller.panel.frame.height - controller.root.chromeHeight)
        #expect(scrollView.frame.maxY == controller.root.bounds.maxY)
    }
}
