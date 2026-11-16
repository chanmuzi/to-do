import AppKit
@_spi(Verification) import Editor
import Models
import Routing
import Testing
@testable import FloatingNotes

/// 단축키와 메뉴가 시키는 동작(`AppCommand`)이 맞는 곳으로 가는지, ⌘Z가 휴지통을 되돌리는지.
@Suite struct AppCommandDispatcherTests {
    private let fixture: AppFixture

    init() throws {
        fixture = try AppFixture(forwardsNoteRoutes: false)
    }

    @Test func screenCommandsBecomeRoutes() {
        defer { fixture.cleanUp() }
        for command: AppCommand in [
            .quickCapture, .toggleNotesHidden, .library, .aiPanel, .newNote, .findNote, .settings, .shortcuts,
        ] {
            fixture.commands.perform(command)
        }

        // 키 창인 노트가 없으면 노트에 붙는 요청은 붙을 곳 없이 간다.
        #expect(fixture.receivedRoutes == [
            .openCapture, .toggleAllNotesHidden, .openLibrary, .openAIPanel(context: nil),
            .newNote(NewNoteRequest()), .openBrowse(anchor: nil), .openSettings, .openShortcuts,
        ])
    }

    /// 지금 노트에 하는 동작은 키 창인 노트가 없으면 아무 일도 하지 않는다.
    @Test func noteCommandsNeedAKeyNote() throws {
        defer { fixture.cleanUp() }
        let (id, _) = try fixture.open(NoteDraft(title: "키 창이 아닌 노트"))
        #expect(fixture.notePanels.keyNoteID == nil)

        for command: AppCommand in [.moreMenu, .editTitle, .togglePin, .setReminder, .moveToSpace, .closeWindow] {
            fixture.commands.perform(command)
        }

        #expect(fixture.receivedRoutes.isEmpty)
        #expect(fixture.notePanels.snapshot(of: id)?.isPinned == true)
        #expect(fixture.notePanels.openNoteIDs == [id])
    }

    @Test func nextNoteMovesThroughOpenNotes() throws {
        defer { fixture.cleanUp() }
        let (first, _) = try fixture.open(NoteDraft(title: "가"))
        let (second, _) = try fixture.open(NoteDraft(title: "나"))
        #expect(fixture.notePanels.frontmostNoteID == second)

        fixture.commands.perform(.nextNote)

        #expect(fixture.notePanels.frontmostNoteID == first)
    }

    /// 아직 화면이 없는 동작은 조용히 넘어가지 않고 적어 둔다.
    @Test func commandsWithoutAScreenAreRecorded() {
        defer { fixture.cleanUp() }
        fixture.commands.perform(.findInNote)
        fixture.commands.perform(.searchAll)

        #expect(fixture.commands.unavailable == [.findInNote, .searchAll])
        #expect(fixture.receivedRoutes.isEmpty)
    }

    // MARK: - 휴지통 되돌리기

    @Test func undoRightAfterTrashRestoresTheNoteWindowAndFolds() throws {
        defer { fixture.cleanUp() }
        var forwarded = 0
        fixture.commands.forwardUndo = { _ in forwarded += 1 }
        let (id, adapter) = try fixture.open(NoteDraft(title: "되돌릴 노트", body: "> 토글\n\t안쪽\n끝"))
        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        adapter.editor.perform(.fold)
        let frame = try #require(fixture.notePanels.snapshot(of: id)).frame

        fixture.notePanels.moveToTrash(id)
        #expect(fixture.notePanels.openNoteIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.noteFile(id).path))
        fixture.commands.undoOrRestoreTrash(nil)

        #expect(forwarded == 0)
        #expect(fixture.notePanels.openNoteIDs == [id])
        #expect(try fixture.fileText(id).hasSuffix("> 토글\n\t안쪽\n끝"))
        // 같은 자리(왼쪽, 위쪽 가장자리, 너비)에 돌아온다. 높이는 내용이 정한다.
        let restored = try #require(fixture.notePanels.snapshot(of: id)).frame
        #expect(restored.minX == frame.minX)
        #expect(restored.maxY == frame.maxY)
        #expect(restored.width == frame.width)
        #expect(fixture.editors.editor(for: id)?.editor.foldedLines == [0])

        // 되돌릴 휴지통이 없으면 글의 실행 취소로 넘긴다.
        fixture.commands.undoOrRestoreTrash(nil)
        #expect(forwarded == 1)
    }

    @Test func undoAfterEditingAnotherNoteGoesToTheTextInstead() throws {
        defer { fixture.cleanUp() }
        var forwarded = 0
        fixture.commands.forwardUndo = { _ in forwarded += 1 }
        let (trashed, _) = try fixture.open(NoteDraft(title: "버릴 노트"))
        let (_, other) = try fixture.open(NoteDraft(title: "다른 노트", body: "처음"))

        fixture.notePanels.moveToTrash(trashed)
        let view = other.editor.textView
        view.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        fixture.commands.undoOrRestoreTrash(nil)

        #expect(forwarded == 1)
        #expect(fixture.notePanels.openNoteIDs.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.noteFile(trashed).path))
    }

    /// 되살리지 못하면(휴지통의 파일이 없어짐) 삼키지 않고 사용자에게 알린다.
    @Test func failedRestoreIsShownToTheUser() throws {
        defer { fixture.cleanUp() }
        var shown: [String] = []
        fixture.commands.presentFailure = { title, _ in shown.append(title) }
        let (id, _) = try fixture.open(NoteDraft(title: "사라질 노트"))
        fixture.notePanels.moveToTrash(id)
        try FileManager.default.removeItem(
            at: fixture.location.trashDirectory.appendingPathComponent("\(id.rawValue).md")
        )

        fixture.commands.undoOrRestoreTrash(nil)

        #expect(shown == ["노트를 되살리지 못했습니다"])
        #expect(fixture.notePanels.openNoteIDs.isEmpty)
    }
}
