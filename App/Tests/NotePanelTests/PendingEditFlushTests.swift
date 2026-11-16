import AppKit
import Models
import Store
import Testing
@testable import NotePanel

/// 편집기가 아직 알리지 않은 글(`NoteBodyEditing.flushPendingChange`)을 창을 내리기 전, 휴지통으로 보내기 전,
/// 앱을 끝내기 전에 받아 두는지.
@Suite @MainActor struct PendingEditFlushTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func open(_ draft: NoteDraft) throws -> (NotePanelCoordinator, NoteID, SpyBodyEditor) {
        let editor = SpyBodyEditor()
        let coordinator = try fixture.makeCoordinator(makeBodyEditor: { _ in editor })
        let note = try fixture.notes.create(draft)
        try coordinator.open(note.id, focus: false)
        return (coordinator, note.id, editor)
    }

    @Test func closingCollectsTextTheEditorHadNotReported() throws {
        let (coordinator, id, editor) = try open(NoteDraft(title: "닫기", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        editor.compose("처음 그리고 늦게 알릴 글")

        coordinator.closeWindow(id)

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(editor.flushCount == 1)
        #expect(try String(contentsOf: fixture.noteFile(id), encoding: .utf8).hasSuffix("처음 그리고 늦게 알릴 글"))
    }

    @Test func trashCollectsTextTheEditorHadNotReported() throws {
        let (coordinator, id, editor) = try open(NoteDraft(title: "휴지통", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        editor.compose("처음 그리고 마지막 글")

        coordinator.moveToTrash(id)

        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(try String(contentsOf: fixture.trashFile(id), encoding: .utf8).hasSuffix("처음 그리고 마지막 글"))
    }

    /// 앱을 끝낼 때 App이 부르는 차례: 떠 있는 창 모두에서 받은 뒤 저장소가 쓴다.
    @Test func flushingEveryWindowBeforeQuitReachesTheFiles() throws {
        let coordinator = try fixture.makeCoordinator(makeBodyEditor: { _ in SpyBodyEditor() })
        defer { fixture.cleanUp(coordinator) }
        let ids = try ["가", "나"].map { try fixture.notes.create(NoteDraft(body: $0)).id }
        for id in ids {
            try coordinator.open(id, focus: false)
            let editor = try #require(coordinator.controllers[id]?.editor as? SpyBodyEditor)
            editor.compose("\(editor.text) 끝내기 직전")
        }

        coordinator.flushPendingEdits()
        try fixture.notes.flushPendingSaves()

        #expect(try String(contentsOf: fixture.noteFile(ids[0]), encoding: .utf8).hasSuffix("가 끝내기 직전"))
        #expect(try String(contentsOf: fixture.noteFile(ids[1]), encoding: .utf8).hasSuffix("나 끝내기 직전"))
    }

    /// 알릴 것이 없으면 아무것도 하지 않는다(저장소에 변경이 생기지 않는다).
    @Test func nothingPendingMeansNoChange() throws {
        let (coordinator, id, editor) = try open(NoteDraft(title: "그대로", body: "처음"))
        defer { fixture.cleanUp(coordinator) }

        coordinator.flushPendingEdits()

        #expect(editor.flushCount == 0)
        #expect(!fixture.notes.hasPendingChanges(id))
    }

    /// 기본 편집기도 조합 중이라 알리지 못한 글을 내놓는다.
    @Test func plainEditorReportsUnnotifiedTextOnceWhenAsked() throws {
        let editor = PlainTextBodyEditor(theme: fixture.theme)
        defer { fixture.cleanUp() }
        editor.text = "처음"
        var notified: [String] = []
        editor.onTextChange = { notified.append($0) }
        let textView = try #require(editor.view as? NSTextView)

        editor.flushPendingChange()
        #expect(notified.isEmpty)
        // 텍스트 뷰의 알림 없이 글만 바뀐 경우(조합 중인 글자).
        textView.textStorage?.replaceCharacters(in: NSRange(location: 2, length: 0), with: "ㅎ")
        editor.flushPendingChange()
        editor.flushPendingChange()

        #expect(notified == ["처음ㅎ"])
    }
}
