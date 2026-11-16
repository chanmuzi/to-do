import AppKit
import Models
import Store
import Testing
@_spi(Verification) @testable import NotePanel

/// 키 입력을 누가 받는지(D-025): 키 창이던 노트가 내려갔을 때, 사용자가 앱을 앞으로 가져왔을 때,
/// 손쉬운 사용 도구가 포커스를 달라고 할 때. 그리고 저절로는 키 창이 되지 않는 때.
///
/// 시험은 실제 키 창을 만들지 않는다(사용자가 다른 앱에 치던 글자를 가져온다). 창이 키 창이 되도록
/// "시켰는지"(`keyRequestCount`)를 보고, 어느 창이 키 창인지는 `isKeyPanel`로 바꿔 넣는다.
@Suite @MainActor struct KeyHandoffTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    /// 노트 셋을 띄운다. 겹친 차례는 띄운 차례다(마지막이 맨 앞).
    private func openNotes(
        _ titles: [String], in coordinator: NotePanelCoordinator
    ) throws -> [NoteID] {
        try titles.map { title in
            let id = try fixture.notes.create(NoteDraft(title: title)).id
            try coordinator.open(id, focus: false)
            return id
        }
    }

    private func requests(_ id: NoteID, in coordinator: NotePanelCoordinator) -> Int {
        coordinator.controllers[id]?.panel.keyRequestCount ?? -1
    }

    /// 그 노트의 창이 키 창인 것처럼 본다.
    private func pretend(_ id: NoteID, isKeyIn coordinator: NotePanelCoordinator) {
        let panel = coordinator.controllers[id]?.panel
        coordinator.isKeyPanel = { $0 === panel }
    }

    // MARK: - 규칙

    @Test func handoffRule() {
        let next = NoteID(rawValue: "next")
        // 키 창이 아니던 창이 내려가면 아무 일도 없다.
        #expect(KeyHandoff.afterDiscarding(wasKey: false, nextVisible: next, afterTrash: true) == .none)
        // 키 창이던 창이 내려가면 다음 노트가 이어받는다(휴지통이든 닫기든).
        #expect(KeyHandoff.afterDiscarding(wasKey: true, nextVisible: next, afterTrash: true) == .makeKey(next))
        #expect(KeyHandoff.afterDiscarding(wasKey: true, nextVisible: next, afterTrash: false) == .makeKey(next))
        // 남은 노트가 없으면: 휴지통으로 보낸 뒤에는 ⌘Z를 받도록 앱을 앞으로, 닫기만 했으면 그대로 둔다.
        #expect(KeyHandoff.afterDiscarding(wasKey: true, nextVisible: nil, afterTrash: true) == .activateApp)
        #expect(KeyHandoff.afterDiscarding(wasKey: true, nextVisible: nil, afterTrash: false) == .none)
    }

    // MARK: - 키 창이던 노트가 내려갔을 때

    /// 검토에서 나온 문제: 키 창인 노트를 휴지통으로 보내면 키 창인 노트가 없어 ⌘Z가 다른 앱으로 갔다.
    @Test func trashingTheKeyNoteHandsKeyToTheFrontmostRemainingNoteAndKeepsTheUndo() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var activations = 0
        coordinator.activateApp = { activations += 1 }
        let ids = try openNotes(["뒤", "가운데", "버릴 노트"], in: coordinator)
        pretend(ids[2], isKeyIn: coordinator)
        #expect(coordinator.keyNoteID == ids[2])

        coordinator.moveToTrash(ids[2])

        // 남은 것 가운데 가장 앞에 겹친 "가운데"가 이어받는다. 앱을 앞으로 가져올 필요는 없다.
        #expect(requests(ids[1], in: coordinator) == 1)
        #expect(requests(ids[0], in: coordinator) == 0)
        #expect(activations == 0)
        // 이어받은 것은 사용자가 다른 노트로 옮겨 간 것이 아니다. ⌘Z는 아직 방금 보낸 노트를 되살린다.
        #expect(coordinator.canUndoTrash)
    }

    @Test func trashingTheLastVisibleKeyNoteActivatesTheAppSoUndoStillArrives() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var activations = 0
        coordinator.activateApp = { activations += 1 }
        let ids = try openNotes(["하나뿐인 노트"], in: coordinator)
        pretend(ids[0], isKeyIn: coordinator)

        coordinator.moveToTrash(ids[0])

        #expect(activations == 1)
        #expect(coordinator.canUndoTrash)
        // 되살린 노트는 키 창이 되라고 시킨다.
        #expect(try coordinator.undoTrash() == ids[0])
        #expect(requests(ids[0], in: coordinator) == 1)
    }

    @Test func closingTheKeyNoteHandsKeyOnButNeverActivatesTheApp() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var activations = 0
        coordinator.activateApp = { activations += 1 }
        let ids = try openNotes(["남는 노트", "닫을 노트"], in: coordinator)
        pretend(ids[1], isKeyIn: coordinator)

        coordinator.closeWindow(ids[1])
        #expect(requests(ids[0], in: coordinator) == 1)

        // 마지막 노트를 닫기만 했으면 되돌릴 것이 없다. 다른 앱의 키 입력을 가져오지 않는다.
        pretend(ids[0], isKeyIn: coordinator)
        coordinator.closeWindow(ids[0])
        #expect(activations == 0)
    }

    @Test func discardingANoteThatWasNotKeyChangesNothing() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var activations = 0
        coordinator.activateApp = { activations += 1 }
        let ids = try openNotes(["하나", "둘", "셋"], in: coordinator)

        coordinator.moveToTrash(ids[2])
        coordinator.closeWindow(ids[1])

        #expect(requests(ids[0], in: coordinator) == 0)
        #expect(activations == 0)
    }

    /// 숨긴 노트는 이어받지 않는다(보이는 노트가 없다).
    @Test func hiddenNotesDoNotTakeKey() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let ids = try openNotes(["하나", "둘"], in: coordinator)
        coordinator.toggleAllHidden()

        #expect(coordinator.focusFrontmostNote() == nil)
        #expect(ids.allSatisfy { requests($0, in: coordinator) == 0 })
    }

    // MARK: - 사용자가 앱을 앞으로 가져왔을 때

    @Test func activatingTheAppMakesTheFrontmostNoteKey() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        #expect(coordinator.focusFrontmostNote() == nil)
        let spy = SpyBodyEditor()
        let front = try fixture.notes.create(NoteDraft(title: "맨 앞"))
        let ids = try openNotes(["뒤"], in: coordinator)
        let withSpy = try fixture.makeCoordinator(makeBodyEditor: { _ in spy })
        defer { fixture.cleanUp(withSpy) }
        try withSpy.open(ids[0], focus: false)
        try withSpy.open(front.id, focus: false)

        #expect(withSpy.focusFrontmostNote() == front.id)

        #expect(requests(front.id, in: withSpy) == 1)
        #expect(requests(ids[0], in: withSpy) == 0)
        // 본문이 입력을 받는다(키보드만으로 이어 쓸 수 있다).
        #expect(spy.focusCount == 1)
        // 이미 키 창인 노트가 있으면 다시 시키지 않는다.
        pretend(ids[0], isKeyIn: withSpy)
        #expect(withSpy.focusFrontmostNote() == ids[0])
        #expect(requests(front.id, in: withSpy) == 1)
        #expect(requests(ids[0], in: withSpy) == 0)
    }

    /// 저절로는 키 창이 되지 않는다: 켤 때 되살린 창, 앞으로 가져오기만 한 창, "모두 보이기"로 돌아온 창.
    @Test func restoringShowingAndUnhidingNeverAskForKey() throws {
        let first = try fixture.makeCoordinator()
        let ids = try openNotes(["하나", "둘"], in: first)
        first.controllers.values.forEach { $0.discardWindow() }

        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        #expect(Set(coordinator.restoreOpenNotes()) == Set(ids))
        try coordinator.open(ids[0], focus: false)
        coordinator.toggleAllHidden()
        coordinator.toggleAllHidden()
        coordinator.setHoverOverride(true, for: ids[0])

        #expect(ids.allSatisfy { requests($0, in: coordinator) == 0 })
        #expect(coordinator.keyNoteID == nil)
        // 시켜야만 된다: 다음 노트로, 본문에 커서 두기, 제목 고치기.
        coordinator.focusBody(of: ids[1])
        coordinator.beginTitleEditing(for: ids[1])
        #expect(requests(ids[1], in: coordinator) == 2)
    }

    // MARK: - 손쉬운 사용

    /// VoiceOver 같은 도구가 창에 포커스를 달라고 하면(AXFocused, AXMain) 사용자가 누른 것처럼 받는다.
    @Test func accessibilityFocusRequestsAreNotRefused() {
        let panel = NotePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 120))
        defer { panel.close() }
        // 시험에서는 실제로 키 창이 되지 않게 꺼 둔다. 시켰는지만 본다.
        panel.allowsKey = false

        panel.setAccessibilityFocused(true)
        #expect(panel.keyRequestCount == 1)
        panel.setAccessibilityMain(true)
        #expect(panel.keyRequestCount == 2)
        // 포커스를 거두는 요청은 키 창을 시키지 않는다.
        panel.setAccessibilityFocused(false)
        panel.setAccessibilityMain(false)
        #expect(panel.keyRequestCount == 2)
        // 요청이 끝난 뒤에는 다시 저절로 키 창이 되지 못한다.
        panel.allowsKey = true
        #expect(!panel.canBecomeKey(during: nil))
    }

    // MARK: - 휴지통 되돌리기의 "바로 뒤"

    /// 검토에서 나온 문제: B에 글을 쓰고, A를 휴지통으로 보내고, B로 돌아가 ⌘Z를 누르면 A가 되살아났다.
    /// B에는 제 실행 취소 기록이 있다. 다른 노트가 키 창이 되거나 노트 창을 누르면 "바로 뒤"가 끝난다.
    @Test func focusingAnotherNoteEndsTheTrashUndo() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let ids = try openNotes(["B", "A"], in: coordinator)
        let other = try #require(coordinator.controllers[ids[0]])

        coordinator.moveToTrash(ids[1])
        #expect(coordinator.canUndoTrash)
        other.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(!coordinator.canUndoTrash)
        #expect(try coordinator.undoTrash() == nil)

        // 이미 키 창인 노트를 누른 경우(키 창 알림이 오지 않는다)도 같다.
        let third = try fixture.notes.create(NoteDraft(title: "C")).id
        try coordinator.open(third, focus: false)
        coordinator.moveToTrash(third)
        #expect(coordinator.canUndoTrash)
        other.panel.onMouseDown?()
        #expect(!coordinator.canUndoTrash)
    }

    /// 되살릴 수 없다는 것이 드러나면 되돌릴 것을 비운다. 남겨 두면 ⌘Z를 계속 삼킨다.
    @Test func restoreThatCanNeverSucceedIsForgotten() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let gone = try openNotes(["휴지통에서 사라질 노트"], in: coordinator)[0]
        coordinator.moveToTrash(gone)
        try FileManager.default.removeItem(at: fixture.trashFile(gone))

        #expect(throws: StoreError.noteNotFound(gone)) { try coordinator.undoTrash() }
        #expect(!coordinator.canUndoTrash)
        #expect(try coordinator.undoTrash() == nil)

        // 같은 이름의 노트가 그사이 생겼다.
        let taken = try openNotes(["같은 이름이 생길 노트"], in: coordinator)[0]
        coordinator.moveToTrash(taken)
        try Data("다른 프로그램이 만든 파일".utf8).write(to: fixture.noteFile(taken))

        #expect(throws: StoreError.noteAlreadyExists(taken)) { try coordinator.undoTrash() }
        #expect(!coordinator.canUndoTrash)
    }

    /// 잠깐의 실패(파일을 옮기지 못함)는 다시 해 볼 수 있게 남긴다.
    @Test func transientRestoreFailureKeepsTheUndo() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let id = try openNotes(["잠깐 못 돌아올 노트"], in: coordinator)[0]
        coordinator.moveToTrash(id)
        let notesDirectory = fixture.location.notesDirectory.path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notesDirectory)

        #expect(throws: StoreError.self) { try coordinator.undoTrash() }
        #expect(coordinator.canUndoTrash)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notesDirectory)
        #expect(try coordinator.undoTrash() == id)
        #expect(coordinator.openNoteIDs == [id])
    }
}
