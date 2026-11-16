import AppKit
import Models
import Store
import Testing
@testable import NotePanel

/// 노트 창이 본문을 편집기에 넣는 때(`NoteBodyEditing`의 약속).
/// 이 창이 한 저장의 알림으로는 넣지 않고, 다른 쪽(다른 프로그램, 이 앱의 다른 곳)이 본문을 바꿨을 때만 넣는다.
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
        #expect(editor.appended.isEmpty)
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

    /// 다른 프로그램이 고친 본문은 `text`에 넣지 않고 `applyOutsideChange(to:)`로 한 번만 넘긴다.
    @Test func externalBodyChangeIsAppliedExactlyOnce() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "바깥", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "처음", with: "다른 프로그램이 고친 글") }
        try fixture.notes.refresh()
        try fixture.notes.refresh()
        #expect(editor.assignments == ["처음"])
        #expect(editor.applied == ["다른 프로그램이 고친 글"])
        #expect(editor.appended.isEmpty)

        // 받은 글 위에서 고친 것은 충돌이 아니고, 그 저장의 알림으로도 다시 넣지 않는다.
        editor.type("다른 프로그램이 고친 글!")
        try fixture.notes.flushPendingSaves()
        #expect(controller.problem == nil)
        #expect(editor.assignments.count == 1)
        #expect(editor.applied.count == 1)
    }

    @Test func revertingToTheFileAppliesTheFilesBody() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(body: "처음"))
        defer { fixture.cleanUp(coordinator) }

        editor.type("처음 내가 쓴 글")
        try fixture.appendOutside("\n파일 쪽", to: controller.noteID)
        try fixture.notes.refresh()
        #expect(editor.assignments == ["처음"])
        #expect(editor.applied.isEmpty)
        controller.resolveProblem(.keepDisk)

        #expect(controller.problem == nil)
        #expect(editor.assignments == ["처음"])
        #expect(editor.applied == ["처음\n파일 쪽"])
    }

    // MARK: - 이 앱의 다른 곳이 쓴 본문(빠른 캡처가 떠 있는 노트에 덧붙임)

    /// 검토에서 나온 문제: 떠 있는 노트에 다른 곳이 한 줄을 덧붙여도 편집기는 옛 글을 들고 있었고,
    /// 다음 입력이 본문 전체를 옛 글로 덮어써 덧붙인 줄이 사라졌다.
    @Test func lineAppendedByAnotherInAppWriterSurvivesTheNextKeystroke() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "캡처", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        try fixture.notes.update(id) { $0.body += "\n- [ ] 캡처한 줄" }

        // 끝에 붙은 글만 넘긴다(편집기가 실행 취소 기록과 조합을 지킬 수 있게). 통째로 넣지 않는다.
        #expect(editor.appended == ["\n- [ ] 캡처한 줄"])
        #expect(editor.assignments == ["처음"])
        #expect(editor.text == "처음\n- [ ] 캡처한 줄")
        #expect(controller.exchangedBody == "처음\n- [ ] 캡처한 줄")

        // 사용자가 이어서 친다. 편집기는 제 글 전체를 알리고, 그것이 저장된다.
        editor.type("내가 친 글 " + editor.text)
        try fixture.notes.flushPendingSaves()

        let file = try String(contentsOf: fixture.noteFile(id), encoding: .utf8)
        #expect(file.hasSuffix("내가 친 글 처음\n- [ ] 캡처한 줄"))
        #expect(controller.problem == nil)
        // 그 저장의 알림은 다시 편집기로 돌아오지 않는다.
        #expect(editor.appended.count == 1)
        #expect(editor.assignments.count == 1)
    }

    /// 같은 일을 기본 편집기(덧붙이기를 따로 구현하지 않은 편집기)로: 통째로 넣는 길로 넘어가도 글은 남는다.
    @Test func appendedLineSurvivesWithAnEditorThatOnlyTakesWholeText() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "처음"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let textView = try #require(controller.editor.view as? NSTextView)

        try fixture.notes.update(note.id) { $0.body += "\n- [ ] 캡처한 줄" }
        #expect(textView.string == "처음\n- [ ] 캡처한 줄")
        textView.insertText("내가 친 글 ", replacementRange: NSRange(location: 0, length: 0))
        try fixture.notes.flushPendingSaves()

        #expect(try fixture.notes.load(note.id).body == "내가 친 글 처음\n- [ ] 캡처한 줄")
    }

    /// 조합 중인 글자(아직 알리지 않은 글)가 있을 때 덧붙여도 조합이 끊기지 않고, 둘 다 남는다.
    @Test func appendDuringACompositionKeepsTheCompositionAndBothTexts() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "조합", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID
        editor.type("처음 글")
        try fixture.notes.flushPendingSaves()
        editor.compose("처음 글ㅎ")

        try fixture.notes.update(id) { $0.body += "\n캡처" }

        #expect(editor.assignments == ["처음"])
        #expect(editor.appended == ["\n캡처"])
        #expect(editor.text == "처음 글ㅎ\n캡처")
        // 조합이 끝나 편집기가 알리면 조합한 글자와 덧붙인 줄이 함께 저장된다.
        editor.flushPendingChange()
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.notes.load(id).body == "처음 글ㅎ\n캡처")
    }

    /// 끝에 붙인 것이 아닌 바꿈(다른 곳이 본문을 고쳐 씀)은 `text`에 넣지 않고 `applyOutsideChange(to:)`로 넘긴다.
    @Test func bodyRewrittenByAnotherInAppWriterIsAppliedNotAssigned() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(body: "- [ ] 할 일"))
        defer { fixture.cleanUp(coordinator) }

        try fixture.notes.update(controller.noteID) { $0.body = "- [x] 할 일" }

        #expect(editor.assignments == ["- [ ] 할 일"])
        #expect(editor.applied == ["- [x] 할 일"])
        #expect(editor.appended.isEmpty)
        #expect(controller.exchangedBody == "- [x] 할 일")
    }

    /// 빠른 캡처는 본문 끝의 빈 줄을 걷어 내고 줄을 붙인다. 끝에 붙인 것이 아니므로 `applyOutsideChange(to:)`로
    /// 넘기고(`text`에 넣지 않는다), 주고받은 본문을 새 본문으로 맞춰 그 뒤의 저장 알림과 입력이 어긋나지 않는다.
    @Test func lineAddedAfterTrimmingTrailingBlankLinesIsAppliedAndSurvivesTyping() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "오늘", body: "쓰던 줄\n\n\n"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID
        // 아직 저장되지 않은 입력이 있는 채로 다른 곳이 본문을 고쳐 쓴다.
        editor.type("쓰던 줄!\n\n\n")

        try fixture.notes.update(id) { $0.body = "쓰던 줄!\n[ ] 우유 사기\n" }

        #expect(editor.assignments == ["쓰던 줄\n\n\n"])
        #expect(editor.appended.isEmpty)
        #expect(editor.applied == ["쓰던 줄!\n[ ] 우유 사기\n"])
        #expect(controller.exchangedBody == "쓰던 줄!\n[ ] 우유 사기\n")

        // 그 뒤의 입력은 받은 글 위에서 저장되고, 그 저장의 알림은 편집기로 돌아오지 않는다.
        editor.type("쓰던 줄!\n[ ] 우유 사기\n이어서 친 글")
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.notes.load(id).body == "쓰던 줄!\n[ ] 우유 사기\n이어서 친 글")
        #expect(editor.applied.count == 1)
        #expect(editor.assignments.count == 1)
        #expect(controller.problem == nil)
    }

    /// `applyOutsideChange(to:)`를 따로 구현하지 않은 편집기(기본 편집기)는 통째로 넣는 길로 넘어간다. 글은 남는다.
    @Test func rewriteReachesAnEditorThatOnlyTakesWholeText() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let note = try fixture.notes.create(NoteDraft(body: "쓰던 줄\n\n"))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        let textView = try #require(controller.editor.view as? NSTextView)

        try fixture.notes.update(note.id) { $0.body = "쓰던 줄\n[ ] 우유 사기\n" }
        #expect(textView.string == "쓰던 줄\n[ ] 우유 사기\n")
        textView.insertText("끝", replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
        try fixture.notes.flushPendingSaves()

        #expect(try fixture.notes.load(note.id).body == "쓰던 줄\n[ ] 우유 사기\n끝")
    }

    /// 더 나쁜 경우: 다른 프로그램이 파일을 제자리에서 고쳤고(아직 알아채지 못함), 그 뒤에 캡처가 덧붙였다.
    /// 그다음 입력이 두 변경을 말없이 덮어쓰면 안 된다. 충돌로 드러나거나 둘 다 남아야 한다.
    @Test func externalEditThenInAppAppendThenTypingNeverLosesTextSilently() throws {
        let (coordinator, controller, editor) = try open(NoteDraft(title: "겹침", body: "처음"))
        defer { fixture.cleanUp(coordinator) }
        let id = controller.noteID

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "처음", with: "밖에서 고친 글") }
        // 캡처가 하는 일: 읽고(충돌 기준이 새로 잡힌다) 끝에 덧붙인다.
        _ = try fixture.notes.load(id)
        try fixture.notes.update(id) { $0.body += "\n캡처" }
        editor.type(editor.text + "!")
        try fixture.notes.flushPendingSaves()

        let file = try String(contentsOf: fixture.noteFile(id), encoding: .utf8)
        let bothSurvived = file.contains("밖에서 고친 글") && file.contains("캡처") && file.hasSuffix("!")
        #expect(controller.problem == .conflict || bothSurvived)
        // 이 저장소에서는 캡처의 쓰기가 밖에서 고친 글 위에 덧붙이고, 편집기가 그 본문을 받는다.
        #expect(editor.text == "밖에서 고친 글\n캡처!")
        #expect(bothSurvived)
    }
}
