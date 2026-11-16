import AppKit
import Models
import Routing
import Store
import Testing
import Theme
@testable import NotePanel

/// 노트 창을 실제로 만들어 크기, 상태 저장, 저장소 연동을 본다.
@Suite @MainActor struct NoteWindowTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func typeText(_ text: String, into controller: NoteWindowController) throws {
        let textView = try #require(controller.editor.view as? NSTextView)
        textView.insertText(text, replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
    }

    // MARK: - 크기와 상태 조합

    @Test func windowAndElementFramesAreIdenticalAcrossHoverAndFocus() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(
            title: "오늘 할 일", body: "하나\n둘", reminder: Date().addingTimeInterval(3600)
        ))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        func measure() -> [CGRect] {
            controller.root.layoutSubtreeIfNeeded()
            return [controller.panel.frame]
                + controller.root.subviews.map(\.frame)
                + controller.root.topRow.subviews.map(\.frame)
        }

        var measured: [[CGRect]] = []
        for focused in [false, true] {
            #expect(controller.panel.makeFirstResponder(focused ? controller.editor.view : nil))
            for hovered in [false, true] {
                controller.hoverOverride = hovered
                measured.append(measure())
            }
        }
        #expect(measured.count == 4)
        #expect(Set(measured).count == 1)
        // 호버로 나타나는 것은 보이지 않을 때도 자리를 차지한다.
        #expect(controller.root.topRow.subviews.filter { $0 is IconButton && !$0.isHidden }.allSatisfy {
            $0.frame.width == fixture.theme.component(.iconButton)
        })
    }

    @Test func hoverRevealsControlsByAlphaOnly() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        coordinator.setPinned(false, for: note.id)

        controller.hoverOverride = false
        let buttons = controller.root.topRow.subviews.compactMap { $0 as? IconButton }.filter { !$0.isHidden }
        #expect(buttons.count == 4)
        #expect(buttons.allSatisfy { $0.alphaValue == 0 })
        #expect(controller.root.cornerButtons.alphaValue == 0)

        controller.hoverOverride = true
        #expect(coordinator.snapshot(of: note.id)?.isHovered == true)
    }

    @Test func heightFollowsTheContentWithTheTopEdgeFixed() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft())
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let theme = fixture.theme
        let empty = controller.panel.frame
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        #expect(empty.height == chrome + theme.lineHeight(.body) + theme.docPadding.top + theme.docPadding.bottom)
        #expect(empty.width == theme.component(.noteWidth))

        try typeText("첫 줄\n둘째 줄\n셋째 줄", into: controller)
        // 움직임이 끝난 뒤의 틀은 창 상태에 바로 적힌다.
        let saved = try #require(fixture.windowState(for: note.id)?.frame?.cgRect)
        #expect(saved.maxY == empty.maxY)
        #expect(saved.minX == empty.minX)
        #expect(saved.height == empty.height + theme.lineHeight(.body) * 2)
        // 본문은 스크롤 영역의 맨 위에서 시작한다.
        #expect(controller.editor.view.frame.origin == .zero)
    }

    @Test func animatedHeightChangeReachesItsTarget() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft())
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let empty = controller.panel.frame

        try typeText("첫 줄\n둘째 줄\n셋째 줄", into: controller)
        let target = try #require(fixture.windowState(for: note.id)?.frame?.cgRect)
        #expect(target.height > empty.height)
        let deadline = Date().addingTimeInterval(3)
        while controller.heightTarget != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.panel.frame == target)
        #expect(try fixture.windowState(for: note.id)?.frame?.cgRect == target)
        #expect(controller.heightTarget == nil)
    }

    // MARK: - 상태 저장과 되살리기

    @Test func restoreBringsBackOnlyOpenNotesAtTheirFrames() throws {
        let first = try fixture.makeCoordinator()
        defer { fixture.cleanUp() }
        let kept = try fixture.notes.create(NoteDraft(title: "남는 노트", body: "한 줄"))
        let closed = try fixture.notes.create(NoteDraft(title: "닫는 노트"))
        try first.open(kept.id, focus: false)
        try first.open(closed.id, focus: false)
        first.setPinned(false, for: kept.id)
        let panel = try #require(first.controllers[kept.id]).panel
        panel.setFrameOrigin(NSPoint(x: 120, y: 240))
        first.controllers[kept.id]?.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        let frame = panel.frame
        first.closeWindow(closed.id)
        first.controllers.values.forEach { $0.discardWindow() }

        let second = try fixture.makeCoordinator()
        defer { second.controllers.values.forEach { $0.discardWindow() } }
        #expect(second.restoreOpenNotes() == [kept.id])
        let restored = try #require(second.snapshot(of: kept.id))
        #expect(restored.frame == frame)
        #expect(!restored.isPinned)
        #expect(restored.level == NSWindow.Level.normal.rawValue)
        #expect(second.snapshot(of: closed.id) == nil)
    }

    @Test func staleSavedHeightIsReplacedByTheContentHeightFromTheSameTopEdge() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "키 큰 틀", body: "한 줄\n두 줄"))
        let saved = CGRect(x: 200, y: 300, width: 400, height: 300)
        try WindowStateStore(location: fixture.location).set(
            NoteWindowState(frame: WindowFrame(saved), isPinned: true, isOpen: true), for: note.id
        )

        let coordinator = try fixture.makeCoordinator()
        defer { coordinator.controllers.values.forEach { $0.discardWindow() } }
        coordinator.restoreOpenNotes()
        let controller = try #require(coordinator.controllers[note.id])
        let theme = fixture.theme

        #expect(controller.panel.frame.maxY == saved.maxY)
        #expect(controller.panel.frame.width == saved.width)
        #expect(controller.panel.frame.height == theme.shape(.chromeHeight) + theme.shape(.borderWidth)
            + theme.lineHeight(.body) * 2 + theme.docPadding.top + theme.docPadding.bottom)
        controller.root.layoutSubtreeIfNeeded()
        #expect(controller.editor.view.frame.origin == .zero)
        let clip = try #require(controller.editor.view.enclosingScrollView?.contentView)
        #expect(clip.bounds.origin == .zero)
        #expect(clip.isFlipped)
        #expect(controller.editor.view.frame.height == clip.bounds.height)
    }

    @Test func newNoteOpensPinnedNextToTheCurrentOne() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let first = try coordinator.createNote()
        let anchor = try #require(coordinator.snapshot(of: first)).frame
        let second = try coordinator.createNote(NewNoteRequest(nextTo: first))
        let opened = try #require(coordinator.snapshot(of: second))

        #expect(coordinator.openNoteIDs == [first, second])
        #expect(opened.isPinned)
        #expect(opened.level == NSWindow.Level.floating.rawValue)
        #expect(opened.frame.maxY == anchor.maxY)
        #expect(!opened.frame.intersects(anchor))
        #expect(FileManager.default.fileExists(atPath: fixture.noteFile(second).path))
    }

    @Test func restoreForgetsNotesWhoseFileIsGone() throws {
        let first = try fixture.makeCoordinator()
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "사라질 노트"))
        try first.open(note.id, focus: false)
        first.controllers.values.forEach { $0.discardWindow() }
        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()

        let second = try fixture.makeCoordinator()
        #expect(second.restoreOpenNotes().isEmpty)
        #expect(try fixture.windowState(for: note.id) == nil)
    }

    // MARK: - 닫기와 휴지통

    @Test func closingKeepsTheNoteAndWritesPendingEdits() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "닫기"))
        try coordinator.open(note.id, focus: false)
        try typeText("닫기 전에 쓴 글", into: try #require(coordinator.controllers[note.id]))

        coordinator.closeWindow(note.id)

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(try String(contentsOf: fixture.noteFile(note.id), encoding: .utf8).hasSuffix("닫기 전에 쓴 글"))
        let state = try #require(try fixture.windowState(for: note.id))
        #expect(!state.isOpen)
        #expect(state.frame != nil)
    }

    @Test func trashMovesTheFileAndForgetsTheWindow() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "버리기", body: "본문"))
        try coordinator.open(note.id, focus: false)

        coordinator.moveToTrash(note.id)

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.noteFile(note.id).path))
        #expect(FileManager.default.fileExists(atPath: fixture.trashFile(note.id).path))
        #expect(try fixture.windowState(for: note.id) == nil)
    }

    @Test func hidingAllKeepsWindowsOpenAndBringsThemBack() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "숨기기"))
        try coordinator.open(note.id, focus: false)

        coordinator.toggleAllHidden()
        #expect(coordinator.areNotesHidden)
        #expect(coordinator.snapshot(of: note.id)?.isVisible == false)
        #expect(try fixture.windowState(for: note.id)?.isOpen == true)

        coordinator.toggleAllHidden()
        #expect(!coordinator.areNotesHidden)
        #expect(coordinator.snapshot(of: note.id)?.isVisible == true)
    }

    // MARK: - 저장소 연동

    @Test func colorAndTitleChangeOnlyTheirOwnFields() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목", body: "본문"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        try typeText(" 더하기", into: controller)
        coordinator.setColor(PaletteID(rawValue: "tint-3"), for: note.id)
        controller.root.topRow.actions.titleChanged("새 제목")

        let stored = try fixture.notes.load(note.id)
        #expect(stored.body == "본문 더하기")
        #expect(stored.colorID == PaletteID(rawValue: "tint-3"))
        #expect(stored.title == "새 제목")
    }

    @Test func titleIsEditedInPlaceWithoutMovingAnything() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목", body: "본문은 그대로"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let topRow = controller.root.topRow
        controller.hoverOverride = true
        topRow.layoutSubtreeIfNeeded()
        let buttonFrames = topRow.subviews.filter { $0 is IconButton }.map(\.frame)
        let windowFrame = controller.panel.frame

        topRow.beginTitleEditing()
        #expect(topRow.isEditingTitle)
        let fieldEditor = try #require(controller.panel.firstResponder as? NSTextView)
        fieldEditor.insertText(" 고침", replacementRange: fieldEditor.selectedRange())
        topRow.layoutSubtreeIfNeeded()

        #expect(try fixture.notes.load(note.id).title == "제목 고침")
        #expect(try fixture.notes.load(note.id).body == "본문은 그대로")
        #expect(topRow.subviews.filter { $0 is IconButton }.map(\.frame) == buttonFrames)
        #expect(controller.panel.frame == windowFrame)

        topRow.endTitleEditing()
        #expect(!topRow.isEditingTitle)
        #expect(controller.note.title == "제목 고침")
    }

    @Test func escapeRestoresTheTitleFromBeforeEditing() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "원래 제목"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        controller.root.topRow.beginTitleEditing()
        let fieldEditor = try #require(controller.panel.firstResponder as? NSTextView)
        fieldEditor.insertText("지울 글", replacementRange: NSRange(location: 0, length: 5))
        #expect(try fixture.notes.load(note.id).title == "지울 글")
        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        #expect(!controller.root.topRow.isEditingTitle)
        #expect(try fixture.notes.load(note.id).title == "원래 제목")
    }

    @Test func externalEditIsReloadedIntoTheWindow() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "바깥", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        try fixture.appendOutside("\n다른 프로그램이 쓴 줄", to: note.id)
        try fixture.notes.refresh()

        #expect(controller.editor.text == "처음\n다른 프로그램이 쓴 줄")
        #expect(controller.problem == nil)
        // 다시 읽었으므로 그 뒤의 편집은 충돌이 아니다.
        try typeText("!", into: controller)
        try fixture.notes.flushPendingSaves()
        #expect(controller.problem == nil)
    }

    @Test func conflictKeepsTheUsersTextAndShowsAnIndicatorUntilResolved() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "충돌", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])

        try typeText(" 내가 쓴 글", into: controller)
        try fixture.appendOutside("\n다른 프로그램이 쓴 줄", to: note.id)
        try fixture.notes.refresh()

        #expect(controller.problem == .conflict)
        #expect(controller.editor.text == "처음 내가 쓴 글")
        #expect(coordinator.snapshot(of: note.id)?.problem != nil)
        // 닫으려 해도 쓰지 못한 글이 있으면 창이 남는다.
        coordinator.closeWindow(note.id)
        #expect(coordinator.openNoteIDs == [note.id])
        #expect(try String(contentsOf: fixture.noteFile(note.id), encoding: .utf8).hasSuffix("다른 프로그램이 쓴 줄"))

        controller.resolveProblem(.keepMine)
        #expect(controller.problem == nil)
        #expect(try String(contentsOf: fixture.noteFile(note.id), encoding: .utf8).hasSuffix("처음 내가 쓴 글"))
    }

    @Test func conflictCanBeResolvedInFavorOfTheFile() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try typeText(" 내가 쓴 글", into: controller)
        try fixture.appendOutside("\n파일 쪽", to: note.id)
        try fixture.notes.refresh()

        controller.resolveProblem(.keepDisk)
        #expect(controller.problem == nil)
        #expect(controller.editor.text == "처음\n파일 쪽")
    }

    @Test func noteRemovedOutsideClosesItsWindow() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "지워질 노트"))
        try coordinator.open(note.id, focus: false)

        try FileManager.default.removeItem(at: fixture.noteFile(note.id))
        try fixture.notes.refresh()

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(try fixture.windowState(for: note.id) == nil)
    }

    @Test func buttonsSendRoutesInsteadOfCallingOtherFeatures() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft())
        try coordinator.open(note.id, focus: false)
        let actions = try #require(coordinator.controllers[note.id]).root.topRow.actions

        actions.search()
        actions.add()
        actions.reminder()

        #expect(fixture.routes == [
            .openBrowse(anchor: note.id),
            .newNote(NewNoteRequest(nextTo: note.id)),
            .openReminderEditor(note.id),
        ])
    }
}
