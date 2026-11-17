import AppKit
import Models
import Routing
import Store
import Testing
import Theme
@testable import NotePanel

/// 노트 창을 실제로 만들어 크기, 상태 저장, 저장소 연동을 본다.
// AppKit 전환의 MainActor 작업이 다른 창 시험에 밀려 대기 제한을 넘지 않도록 순차 실행한다.
@Suite(.serialized) @MainActor struct NoteWindowTests {
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

    @Test func hoverRevealsControlsByAlphaOnly() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제목"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        coordinator.setPinned(false, for: note.id)

        controller.hoverOverride = false
        let buttons = controller.root.topRow.subviews.compactMap { $0 as? IconButton }.filter { !$0.isHidden }
        // 더 보기, 새 노트, 꺼진 핀(돋보기는 더 보기 메뉴로 옮겼다).
        #expect(buttons.count == 3)
        #expect(buttons.allSatisfy { $0.alphaValue == 0 })
        #expect(controller.root.cornerButtons.alphaValue == 0)

        controller.root.layoutSubtreeIfNeeded()
        let frames = buttons.map(\.frame) + [controller.root.cornerButtons.frame, controller.panel.frame]

        controller.hoverOverride = true
        #expect(coordinator.snapshot(of: note.id)?.isHovered == true)
        // 알파가 실제로 1이 되고(`dur` 동안), 자리와 창 크기는 그대로다.
        #expect(await fixture.wait {
            buttons.allSatisfy { $0.alphaValue == 1 } && controller.root.cornerButtons.alphaValue == 1
        })
        controller.root.layoutSubtreeIfNeeded()
        #expect(buttons.map(\.frame) + [controller.root.cornerButtons.frame, controller.panel.frame] == frames)
        #expect(buttons.allSatisfy { !$0.isHidden })

        controller.hoverOverride = false
        #expect(await fixture.wait {
            buttons.allSatisfy { $0.alphaValue == 0 } && controller.root.cornerButtons.alphaValue == 0
        })
    }

    @Test func heightFollowsTheContentWithTheTopEdgeFixed() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft())
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let theme = fixture.theme
        let empty = controller.panel.frame
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        // 빈 노트도 본문 네 줄만큼의 높이다(`note-body-lines-min`, D-031).
        let minLines = CGFloat(theme.count(.noteBodyLinesMin))
        #expect(minLines == 4)
        #expect(empty.height
            == chrome + theme.lineHeight(.body) * minLines + theme.docPadding.top + theme.docPadding.bottom)
        #expect(empty.width == theme.component(.noteWidth))

        try typeText("첫 줄\n둘째 줄\n셋째 줄\n넷째 줄\n다섯째 줄\n여섯째 줄", into: controller)
        // 높이가 움직이는 동안에도 위쪽 가장자리는 제자리다.
        var tops: Set<CGFloat> = [controller.panel.frame.maxY]
        #expect(await fixture.wait {
            tops.insert(controller.panel.frame.maxY)
            return controller.heightTarget == nil
        })
        #expect(tops == [empty.maxY])
        // 창의 실제 틀이 내용을 따라갔다.
        let grown = controller.panel.frame
        #expect(grown.maxY == empty.maxY)
        #expect(grown.minX == empty.minX)
        #expect(grown.width == empty.width)
        #expect(grown.height == empty.height + theme.lineHeight(.body) * 2)
        #expect(try fixture.windowState(for: note.id)?.frame?.cgRect == grown)
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

        try typeText("첫 줄\n둘째 줄\n셋째 줄\n넷째 줄\n다섯째 줄\n여섯째 줄", into: controller)
        let target = try #require(fixture.windowState(for: note.id)?.frame?.cgRect)
        #expect(target.height > empty.height)
        // 움직임이 실제로 시작됐다: 창은 아직 처음 높이이고, 목표를 향해 가는 중이다.
        // ("동작 줄이기"가 켜져 있으면 움직이지 않고 바로 바뀐다.)
        #expect((controller.heightAnimation != nil) == fixture.animates)
        #expect(controller.heightTarget == (fixture.animates ? target.height : nil))
        #expect(controller.panel.frame.height == (fixture.animates ? empty.height : target.height))
        #expect(await fixture.wait { controller.heightTarget == nil })
        #expect(controller.heightAnimation == nil)
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
        let note = try fixture.notes.create(NoteDraft(title: "키 큰 틀", body: "하나\n둘\n셋\n넷\n다섯\n여섯"))
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
            + theme.lineHeight(.body) * 6 + theme.docPadding.top + theme.docPadding.bottom)
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

        actions.add()
        actions.reminder()

        #expect(fixture.routes == [
            .newNote(NewNoteRequest(nextTo: note.id)),
            .openReminderEditor(note.id),
        ])
    }

    // MARK: - 검토에서 나온 것

    /// 밖에서 바뀐 글을 받은 뒤의 ⌘Z는 옛 글의 범위를 건드리지 않는다(예전에는 NSRangeException으로 죽었다).
    @Test func undoAfterAnExternalReloadDoesNotTouchTheOldText() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "실행 취소", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let textView = try #require(controller.editor.view as? NSTextView)

        try typeText(" 그리고 아주 길게 이어서 친 글", into: controller)
        try fixture.notes.flushPendingSaves()
        try fixture.rewriteOutside(note.id) { $0.replacingOccurrences(of: "처음 그리고 아주 길게 이어서 친 글", with: "짧") }
        try fixture.notes.refresh()
        #expect(controller.editor.text == "짧")

        let undoManager = try #require(textView.undoManager)
        #expect(!undoManager.canUndo)
        undoManager.undo()
        #expect(controller.editor.text == "짧")
        #expect(controller.problem == nil)

        // "파일의 내용으로 되돌리기"도 같은 길을 지난다.
        try typeText(" 내가 길게 덧붙인 글", into: controller)
        try fixture.rewriteOutside(note.id) { $0.replacingOccurrences(of: "짧", with: "밖") }
        try fixture.notes.refresh()
        #expect(controller.problem == .conflict)
        controller.resolveProblem(.keepDisk)
        #expect(controller.editor.text == "밖")
        #expect(!undoManager.canUndo)
        undoManager.undo()
        #expect(controller.editor.text == "밖")
    }

    /// "다시 저장"은 이 노트의 실패만 본다. 다른 노트의 충돌이 이 노트의 표시가 되지 않는다.
    @Test func retrySaveIgnoresOtherNotesFailures() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let noteA = try fixture.notes.create(NoteDraft(title: "A"))
        let noteB = try fixture.notes.create(NoteDraft(title: "B", body: "처음"))
        try coordinator.open(noteA.id, focus: false)
        try coordinator.open(noteB.id, focus: false)
        let controllerA = try #require(coordinator.controllers[noteA.id])
        let controllerB = try #require(coordinator.controllers[noteB.id])
        try typeText(" 내 글", into: controllerB)
        try fixture.appendOutside("\n밖에서", to: noteB.id)
        try fixture.notes.refresh()
        #expect(controllerB.problem == .conflict)
        controllerA.problem = .saveFailed(message: "디스크가 잠깐 가득 찼습니다")

        controllerA.resolveProblem(.retrySave)

        #expect(controllerA.problem == nil)
        #expect(controllerB.problem == .conflict)
        #expect(fixture.logs.contains { $0.contains(noteB.id.rawValue) })
    }

    /// 저장에 실패한 노트의 파일을 그사이 다른 프로그램이 고쳤으면 "다시 저장"은 충돌로 넘어가
    /// 내 내용으로 저장할지 파일의 내용으로 되돌릴지 고르게 한다.
    @Test func retrySaveTurnsIntoAConflictWhenTheFileChangedOutside() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "A", body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try typeText(" 내 글", into: controller)
        controller.problem = .saveFailed(message: "쓰지 못했습니다")
        try fixture.appendOutside("\n밖에서", to: note.id)

        controller.resolveProblem(.retrySave)
        #expect(controller.problem == .conflict)

        controller.resolveProblem(.keepMine)
        #expect(controller.problem == nil)
        #expect(try String(contentsOf: fixture.noteFile(note.id), encoding: .utf8).hasSuffix("처음 내 글"))
    }

    /// 노트 창은 눌러도 앱을 앞으로 가져오지 않는다. 키 창이 될 때 제자리에서 고친 파일을 다시 읽는다.
    @Test func becomingKeyPicksUpInPlaceExternalEdits() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "제자리", body: "처음"))
        let other = try fixture.notes.create(NoteDraft(title: "다른 노트", body: "그대로"))
        try coordinator.open(note.id, focus: false)
        try coordinator.open(other.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        try fixture.appendOutside("\n제자리에서 고친 줄", to: note.id)
        #expect(controller.editor.text == "처음")

        // 어느 노트 창이 키 창이 되든 폴더를 다시 훑는다.
        coordinator.controllers[other.id]?.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(controller.editor.text == "처음\n제자리에서 고친 줄")
        #expect(controller.note.body == "처음\n제자리에서 고친 줄")
        #expect(controller.problem == nil)
    }

    /// 누를 수 있는 것은 모두 제 영역의 커서를 화살표로 밝힌다(규칙 9). 본문 위에 겹친 버튼도 그렇다.
    @Test func everyClickableControlDeclaresTheArrowCursor() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(
            title: "커서", body: "본문", reminder: Date().addingTimeInterval(3600)
        ))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        controller.hoverOverride = true
        controller.root.layoutSubtreeIfNeeded()

        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        let all = descendants(of: controller.root)
        let pressable = all.filter { $0 is IconButton || $0 is ReminderBadgeView }
        // 상단 줄의 버튼 넷(더 보기, 새 노트, 저장 문제 표시, 핀)과 리마인더, 오른쪽 아래의 휴지통과 닫기.
        #expect(pressable.count == 7)
        let clickables = pressable.compactMap { $0 as? ClickableView }
        #expect(clickables.count == pressable.count)
        for view in clickables {
            view.resetCursorRects()
            #expect(view.declaredCursorRects == [view.bounds])
            #expect(view.bounds.width > 0 || view.isHidden)
        }
        // 휴지통과 닫기는 본문(글자 칸) 위에 겹쳐 있다.
        let body = try #require(controller.editor.view.enclosingScrollView)
        #expect(body.frame.intersects(controller.root.cornerButtons.frame))
        #expect(controller.root.cornerButtons.subviews.allSatisfy { $0 is ClickableView })
    }

    /// 저장 문제 표시는 `dur` 동안 나타나고 사라지며, 자리를 미리 차지하는 것들을 밀지 않는다(규칙 7, 8).
    @Test func problemIndicatorFadesWithoutMovingReservedSlots() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(
            title: "아주 긴 제목이라서 호버 아이콘 자리 앞에서 잘리는 노트의 제목입니다 정말로 깁니다",
            body: "처음", reminder: Date().addingTimeInterval(3600)
        ))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let topRow = controller.root.topRow
        controller.hoverOverride = true
        topRow.layoutSubtreeIfNeeded()
        let buttons = topRow.subviews.compactMap { $0 as? IconButton }
        let indicator = try #require(buttons.first { $0.isHidden })
        let reserved = topRow.subviews.filter { ($0 is IconButton && $0 !== indicator) || $0 is ReminderBadgeView }
        let reservedFrames = reserved.map(\.frame)
        let title = try #require(topRow.subviews.first { $0 is TitleField })
        let titleFrame = title.frame

        try typeText(" 내 글", into: controller)
        try fixture.appendOutside("\n밖에서", to: note.id)
        try fixture.notes.refresh()
        #expect(controller.problem == .conflict)
        #expect(!indicator.isHidden)
        #expect(await fixture.wait { indicator.alphaValue == 1 })
        topRow.layoutSubtreeIfNeeded()
        #expect(reserved.map(\.frame) == reservedFrames)
        #expect(controller.panel.frame.width == fixture.theme.component(.noteWidth))
        // 긴 제목이 잘리는 자리만 표시 앞으로 당겨진다.
        #expect(title.frame.minX == titleFrame.minX)
        #expect(title.frame.maxX == indicator.frame.minX - fixture.theme.component(.chromeGap))
        #expect(indicator.frame.maxX == reserved.map(\.frame.minX).min()! - fixture.theme.component(.iconButtonGap))

        controller.resolveProblem(.keepMine)
        #expect(controller.problem == nil)
        // 사라지는 동안에는 숨기지 않고 자리도 지킨다.
        if fixture.animates {
            #expect(!indicator.isHidden)
            topRow.layoutSubtreeIfNeeded()
            #expect(title.frame.maxX == indicator.frame.minX - fixture.theme.component(.chromeGap))
        }
        #expect(await fixture.wait { indicator.isHidden })
        #expect(indicator.alphaValue == 0)
        topRow.layoutSubtreeIfNeeded()
        #expect(title.frame == titleFrame)
        #expect(reserved.map(\.frame) == reservedFrames)
    }

    /// 리마인더가 생기고 없어질 때도 `dur` 동안 나타나고 사라진다(규칙 8).
    @Test func reminderBadgeFadesInAndOut() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(title: "리마인더"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let topRow = controller.root.topRow
        let badge = try #require(topRow.subviews.first { $0 is ReminderBadgeView })
        #expect(badge.isHidden)
        #expect(badge.alphaValue == 0)

        try fixture.notes.update(note.id) { $0.reminder = Date().addingTimeInterval(3600) }
        #expect(!badge.isHidden)
        #expect(await fixture.wait { badge.alphaValue == 1 })
        topRow.layoutSubtreeIfNeeded()
        let shown = badge.frame
        #expect(shown.width > 0)

        try fixture.notes.update(note.id) { $0.reminder = nil }
        // 사라지는 동안에는 마지막 자리에 그대로 있다.
        if fixture.animates {
            #expect(!badge.isHidden)
            topRow.layoutSubtreeIfNeeded()
            #expect(badge.frame == shown)
        }
        #expect(await fixture.wait { badge.isHidden })
        #expect(badge.alphaValue == 0)
    }

    /// 숨긴 중에 노트 하나에 커서를 두면 숨김이 모두 풀린다. 한 창만 보이는 어중간한 상태는 없다.
    @Test func focusingOrOpeningANoteWhileHiddenRevealsEveryNote() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let first = try fixture.notes.create(NoteDraft(title: "하나"))
        let second = try fixture.notes.create(NoteDraft(title: "둘"))
        try coordinator.open(first.id, focus: false)
        try coordinator.open(second.id, focus: false)
        func visible() -> [Bool?] { [first.id, second.id].map { coordinator.snapshot(of: $0)?.isVisible } }

        coordinator.toggleAllHidden()
        #expect(visible() == [false, false])
        coordinator.focusBody(of: first.id)
        #expect(!coordinator.areNotesHidden)
        #expect(visible() == [true, true])

        coordinator.toggleAllHidden()
        try coordinator.open(second.id, focus: false)
        #expect(!coordinator.areNotesHidden)
        #expect(visible() == [true, true])

        coordinator.toggleAllHidden()
        let created = try coordinator.createNote()
        #expect(!coordinator.areNotesHidden)
        #expect(visible() == [true, true])
        #expect(coordinator.snapshot(of: created)?.isVisible == true)
        // 없는 노트를 가리키면 아무것도 바뀌지 않는다.
        coordinator.toggleAllHidden()
        coordinator.focusBody(of: NoteID(rawValue: "none"))
        #expect(coordinator.areNotesHidden)
    }

    /// 다시 켜면 창이 겹친 앞뒤가 지난번과 같다.
    @Test func restoreKeepsTheFrontToBackOrder() throws {
        let first = try fixture.makeCoordinator()
        defer { fixture.cleanUp() }
        let ids = try (1...3).map { try fixture.notes.create(NoteDraft(title: "노트 \($0)")).id }
        for id in ids { try first.open(id, focus: false) }
        // 처음 띄운 노트를 눌러 맨 앞으로 가져왔다.
        first.controllers[ids[0]]?.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        first.controllers.values.forEach { $0.discardWindow() }

        let second = try fixture.makeCoordinator()
        defer { second.controllers.values.forEach { $0.discardWindow() } }
        #expect(second.restoreOpenNotes() == [ids[1], ids[2], ids[0]])
        // 실제 창도 그 차례로 겹쳐 있다(앞에서 뒤로).
        let numbers = [ids[0], ids[2], ids[1]].compactMap { second.snapshot(of: $0)?.windowNumber }
        let onScreen = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue).filter(numbers.contains)
        #expect(onScreen == numbers)
    }

    /// 조합 중이던 글자는 편집이 끝나며 확정된다. 저장소의 제목이 칸에 보이는 것과 같아야 한다.
    @Test func endingTitleEditingCommitsTheFinalValueIncludingMarkedText() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft())
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let topRow = controller.root.topRow
        let field = try #require(topRow.subviews.compactMap { $0 as? TitleField }.first)

        topRow.beginTitleEditing()
        let fieldEditor = try #require(controller.panel.firstResponder as? NSTextView)
        fieldEditor.insertText("t", replacementRange: fieldEditor.selectedRange())
        fieldEditor.setMarkedText(
            "ㅎ", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        topRow.endTitleEditing()

        #expect(!topRow.isEditingTitle)
        #expect(field.stringValue == "tㅎ")
        #expect(try fixture.notes.load(note.id).title == field.stringValue)
        #expect(controller.note.title == "tㅎ")
    }
}
