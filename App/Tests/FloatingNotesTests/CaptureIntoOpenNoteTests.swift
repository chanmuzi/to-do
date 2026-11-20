import AppKit
@_spi(Verification) import Capture
import Foundation
import Models
import NotePanel
import Routing
import Testing
@testable import FloatingNotes

/// `QuickPanelResultsTests.captureIntoTheOpenTodayNoteShowsInItsWindowAndSurvivesLaterTyping`의 이어짐:
/// 떠 있는 오늘 노트에 캡처한 줄이 그 창의 편집기에 어떤 길로 닿는지. 실제 편집기 대신 부름을 적어 두는
/// 편집기(`CaretSpyEditor`)를 끼워, 노트 창이 밖에서 바뀐 본문을 `text`에 통째로 넣지 않고
/// `appendFromOutside(_:)`나 `applyOutsideChange(to:)`로 넘기는지 본다(통째로 넣으면 실제 편집기는 실행 취소
/// 기록을 비우고 커서와 접힘을 잃는다).
/// 한 번에 하나씩 돈다(`.serialized`): 창을 띄우는 시험이 한꺼번에 시작하면 메인 액터가 밀려, 전환 시간을
/// 기다리는 다른 시험이 제때 차례를 받지 못한다.
@Suite(.serialized) struct CaptureIntoOpenNoteTests {
    private let fixture: WiringFixture
    private let spies = SpyBox()

    init() throws {
        let spies = spies
        fixture = try WiringFixture(makeBodyEditor: { _ in
            let editor = CaretSpyEditor()
            spies.editors.append(editor)
            return editor
        })
    }

    private final class SpyBox {
        var editors: [CaretSpyEditor] = []
    }

    private func capture(_ text: String) throws {
        fixture.router.route(.openCapture)
        try #require(fixture.capture.inputView)
            .insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.capture.performSubmit()
    }

    /// (가) 커서가 본문 맨 끝, 빈 마지막 줄에 있다. 붙은 줄은 끝에 붙은 글로만 넘어가고(`appendFromOutside`),
    /// 이어서 친 글은 붙은 줄 앞에 끼지 않고 제 줄에 남는다.
    @Test func caretOnTheEmptyLastLineKeepsTypingOnItsOwnLine() throws {
        defer { fixture.cleanUp() }
        let today = try fixture.open("오늘", body: "쓰던 줄\n")
        let editor = try #require(spies.editors.first)
        editor.caret = ("쓰던 줄\n" as NSString).length
        // 아직 저장되지 않은 입력이 있는 채로 캡처한다.
        editor.type("방금 친 줄\n")
        fixture.pretendKey(today)

        try capture("우유 사기")

        #expect(try fixture.notes.list().notes.count == 1)
        #expect(editor.assignments == ["쓰던 줄\n"])
        #expect(editor.appended == ["[ ] 우유 사기\n"])
        #expect(editor.applied.isEmpty)
        #expect(editor.text == "쓰던 줄\n방금 친 줄\n[ ] 우유 사기\n")
        #expect(fixture.keyRequests(today) == 1)

        editor.type("이어서 친 글")
        try fixture.notes.flushPendingSaves()
        let final = "쓰던 줄\n방금 친 줄\n[ ] 우유 사기\n이어서 친 글"
        #expect(try fixture.fileText(today).hasSuffix("---\n" + final))
        #expect(editor.text == final)
        // 그 저장의 알림으로는 편집기에 아무것도 넣지 않는다.
        #expect(editor.assignments.count == 1)
        #expect(editor.appended.count == 1)
        #expect(editor.applied.isEmpty)
        #expect(fixture.shownFailures.isEmpty)
    }

    /// (나) 본문이 빈 줄로 끝난다. 캡처는 끝의 빈 줄을 걷어 내고 붙이므로 끝에 붙인 것이 아니다. 그래도
    /// `text`에 통째로 넣지 않고 `applyOutsideChange(to:)`로 넘긴다. 이어서 친 글은 제 줄에 남는다.
    @Test func bodyEndingInABlankLineIsAppliedAsAnOutsideChange() throws {
        defer { fixture.cleanUp() }
        let body = "쓰던 줄\n\n"
        let today = try fixture.open("오늘", body: body)
        let editor = try #require(spies.editors.first)
        editor.caret = (body as NSString).length
        fixture.pretendKey(today)

        try capture("우유 사기")

        let captured = "쓰던 줄\n[ ] 우유 사기\n"
        #expect(editor.assignments == [body])
        #expect(editor.appended.isEmpty)
        #expect(editor.applied == [captured])
        #expect(editor.text == captured)
        #expect(try fixture.fileText(today).hasSuffix("---\n" + captured))

        editor.type("이어서 친 글")
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.fileText(today).hasSuffix("---\n" + captured + "이어서 친 글"))

        // 한 번 더 캡처하면 이번에는 끝에 붙은 글이다. 어느 쪽이든 `text`에는 넣지 않는다.
        try capture("빵 사기")
        #expect(editor.assignments == [body])
        #expect(editor.applied.count + editor.appended.count == 2)
        // 이번 본문은 줄바꿈으로 끝나지 않으므로 붙인 줄 뒤에도 줄바꿈을 넣지 않는다(D-162).
        #expect(editor.text == captured + "이어서 친 글\n[ ] 빵 사기")
        #expect(try fixture.fileText(today).hasSuffix(captured + "이어서 친 글\n[ ] 빵 사기"))
        #expect(fixture.shownFailures.isEmpty)
    }

    /// 커서가 글 가운데 있으면 붙은 줄이 커서를 옮기지 않는다. 이어서 친 글은 치던 자리에 들어간다.
    @Test func caretInTheMiddleStaysWhereItWas() throws {
        defer { fixture.cleanUp() }
        let today = try fixture.open("오늘", body: "쓰던 줄\n\n")
        let editor = try #require(spies.editors.first)
        editor.caret = 2
        fixture.pretendKey(today)

        try capture("우유 사기")
        editor.type("!")
        try fixture.notes.flushPendingSaves()

        #expect(editor.assignments.count == 1)
        #expect(try fixture.fileText(today).hasSuffix("---\n쓰던! 줄\n[ ] 우유 사기\n"))
    }
}
