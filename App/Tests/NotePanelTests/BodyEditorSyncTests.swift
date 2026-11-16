import AppKit
import Models
import Store
import Testing
@testable import NotePanel

/// 노트 창이 본문을 편집기에 넣는 때(`NoteBodyEditing`의 약속).
/// 이 앱이 한 저장의 알림으로는 넣지 않고, 다른 쪽이 본문을 바꿨을 때만 넣는다.
@Suite @MainActor struct BodyEditorSyncTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func open(
        _ draft: NoteDraft, normalizesLineEndings: Bool = false
    ) throws -> (NotePanelCoordinator, NoteWindowController, SpyBodyEditor) {
        let editor = SpyBodyEditor(normalizesLineEndings: normalizesLineEndings)
        let coordinator = try fixture.makeCoordinator(makeBodyEditor: { _ in editor })
        let note = try fixture.notes.create(draft)
        try coordinator.open(note.id, focus: false)
        return (coordinator, try #require(coordinator.controllers[note.id]), editor)
    }

    @Test func autosaveEchoDoesNotPushStaleTextOverAnInFlightComposition() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "조합", body: "abc"))
        defer { fixture.cleanUp(coordinator) }
        #expect(editor.assignments == ["abc"])

        editor.type("abcd")
        editor.compose("abcd한")
        try fixture.notes.flushPendingSaves() // 자동 저장이 돈 것과 같다: .updated/.local

        #expect(editor.assignments == ["abc"])
        #expect(editor.text == "abcd한")
        #expect(controller.note.body == "abcd")
        #expect(try String(contentsOf: fixture.noteFile(controller.noteID), encoding: .utf8).hasSuffix("abcd"))
    }

    @Test func everyLocalWriteLeavesTheEditorAlone() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "제목", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        editor.type("처음 고침")
        editor.compose("처음 고침ㅎ")
        // 색 변경(곧바로 쓰기), 제목 자동 저장, 다른 기능이 한 저장.
        coordinator.setColor(PaletteID(rawValue: "tint-2"), for: id)
        controller.root.topRow.actions.titleChanged("새 제목")
        try fixture.notes.flushPendingSaves()
        try fixture.notes.update(id) { $0.reminder = Date(timeIntervalSince1970: 2_000_000_000) }
        // 충돌을 "내가 고친 내용으로 저장"으로 푼다.
        editor.type("처음 고침 더")
        editor.compose("처음 고침 더ㅎ")
        try fixture.appendOutside("\n밖에서 쓴 줄", to: id)
        try fixture.notes.refresh()
        #expect(controller.problem == .conflict)
        controller.resolveProblem(.keepMine)
        #expect(controller.problem == nil)
        // 다시 저장.
        controller.resolveProblem(.retrySave)

        #expect(editor.assignments == ["처음"])
        #expect(editor.text == "처음 고침 더ㅎ")
        #expect(controller.note.title == "새 제목")
        #expect(controller.note.colorID == PaletteID(rawValue: "tint-2"))
        #expect(controller.note.reminder != nil)
        #expect(try fixture.notes.load(id).body == "처음 고침 더")
    }

    /// 편집기가 받은 글을 제 표기로 고쳐 보여도(CRLF를 LF로) 바뀌지 않은 본문을 다시 넣지 않는다.
    @Test func unchangedBodyIsNotReassignedToANormalisingEditor() throws {
        let (coordinator, controller, editor) = try open(
            NoteDraft(title: "줄바꿈", body: "A\r\nB"), normalizesLineEndings: true
        )
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID
        #expect(editor.text == "A\nB")

        controller.root.topRow.actions.titleChanged("제목 자동 저장")
        try fixture.notes.flushPendingSaves()
        coordinator.setColor(PaletteID(rawValue: "tint-1"), for: id)
        // 다른 프로그램이 제목만 고쳤다. 본문은 그대로다.
        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "제목 자동 저장", with: "밖에서 고친 제목") }
        try fixture.notes.refresh()

        #expect(controller.note.title == "밖에서 고친 제목")
        #expect(editor.assignments == ["A\r\nB"])
        #expect(try String(contentsOf: fixture.noteFile(id), encoding: .utf8).hasSuffix("A\r\nB"))
    }

    @Test func externalBodyChangeIsAssignedExactlyOnce() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "바깥", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        try fixture.appendOutside("\n다른 프로그램이 쓴 줄", to: id)
        try fixture.notes.refresh()
        try fixture.notes.refresh()
        #expect(editor.assignments == ["처음", "처음\n다른 프로그램이 쓴 줄"])

        // 받은 글 위에서 고친 것은 충돌이 아니고, 그 저장의 알림으로도 다시 넣지 않는다.
        editor.type("처음\n다른 프로그램이 쓴 줄!")
        try fixture.notes.flushPendingSaves()
        #expect(controller.problem == nil)
        #expect(editor.assignments.count == 2)
    }

    @Test func revertingToTheFileAssignsTheFilesBody() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(body: "처음"))
        defer { fixture.cleanUp(coordinator) }

        editor.type("처음 내가 쓴 글")
        try fixture.appendOutside("\n파일 쪽", to: controller.noteID)
        try fixture.notes.refresh()
        #expect(editor.assignments == ["처음"])
        controller.resolveProblem(.keepDisk)

        #expect(controller.problem == nil)
        #expect(editor.assignments == ["처음", "처음\n파일 쪽"])
    }
}
