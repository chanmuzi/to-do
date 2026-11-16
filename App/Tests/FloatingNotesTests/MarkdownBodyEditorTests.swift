import AppKit
@_spi(Verification) import Editor
import Models
import NotePanel
import Store
import Testing
import Theme
@testable import FloatingNotes

/// Markdown 편집기를 노트 창의 본문 자리에 끼운 어댑터가 `NoteBodyEditing`의 약속을 지키는지.
/// 실제 노트 창과 저장소를 붙여, 편집기의 입력 경로(`insertText`)로 본다.
@Suite struct MarkdownBodyEditorTests {
    private let fixture: AppFixture

    init() throws {
        fixture = try AppFixture()
    }

    private func type(_ text: String, into adapter: MarkdownBodyEditor) {
        let view = adapter.editor.textView
        adapter.editor.selectedRange = NSRange(location: (adapter.editor.text as NSString).length, length: 0)
        for character in text {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
    }

    // MARK: - 화면

    @Test func documentViewSitsInThePanelsScrollViewAndTheWindowFollowsItsHeight() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "높이", body: "한 줄\n두 줄\n세 줄"))
        let window = try #require(fixture.notePanels.window(for: id))
        let theme = fixture.theme
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        let padding = theme.docPadding

        #expect(adapter.view.isFlipped)
        let scrollView = try #require(adapter.view.enclosingScrollView)
        #expect(scrollView.documentView === adapter.view)
        // 안쪽 여백은 편집기가 넣는다: 내용 높이는 줄 셋과 위아래 여백이다.
        #expect(adapter.editor.contentHeight == theme.lineHeight(.body) * 3 + padding.top + padding.bottom)
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)

        window.contentView?.layoutSubtreeIfNeeded()
        #expect(scrollView.frame.height == adapter.editor.contentHeight)
        #expect(adapter.view.frame.width == scrollView.contentSize.width)
        #expect(adapter.view.frame.origin == .zero)
        #expect(scrollView.contentView.bounds.origin == .zero)
        // 내용이 다 보인다(스크롤할 것이 없다).
        #expect(adapter.view.frame.height <= scrollView.contentSize.height + 0.5)
    }

    @Test func typingGrowsTheWindowFromTheSameTopEdge() async throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "늘어남", body: "한 줄"))
        let window = try #require(fixture.notePanels.window(for: id))
        let top = window.frame.maxY
        let before = window.frame.height

        type("\n둘\n셋", into: adapter)
        let target = before + fixture.theme.lineHeight(.body) * 2
        let deadline = Date().addingTimeInterval(3)
        while window.frame.height != target, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }

        #expect(window.frame.height == target)
        #expect(window.frame.maxY == top)
    }

    /// 커서가 들어간 줄에서 감췄던 주소가 보여 줄이 넘어가고, 그 줄에 글자를 쳐 줄이 더 높아져도
    /// 창 높이가 내용을 끝까지 따라간다. 본문이 스크롤되지 않는다.
    @Test func windowFollowsHeightChangesOfARevealedWrappedLine() async throws {
        defer { fixture.cleanUp() }
        let body = "## 아이디어\n> 참고 링크\n\t- [PR #482 포커스 투명도](https://github.com/example/floating-notes/pull/482)"
        let (id, adapter) = try fixture.open(NoteDraft(title: "링크", body: body))
        let window = try #require(fixture.notePanels.window(for: id))
        let chrome = fixture.theme.shape(.chromeHeight) + fixture.theme.shape(.borderWidth)
        let scrollView = try #require(adapter.view.enclosingScrollView)
        func settle() async throws {
            let deadline = Date().addingTimeInterval(3)
            while window.frame.height != chrome + adapter.editor.contentHeight, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(250))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let closed = window.frame.height
        // 키 창이 될 수 없는 시험 환경에서도 편집 중인 모양을 본다.
        adapter.editor.forcesActiveAppearance = true
        #expect(window.makeFirstResponder(adapter.view))

        adapter.editor.selectedRange = NSRange(location: (body as NSString).length, length: 0)
        try await settle()
        #expect(window.frame.height > closed)
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)

        type("가나", into: adapter)
        try await settle()
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)
        #expect(scrollView.contentView.bounds.origin == .zero)
        #expect(scrollView.frame.height == adapter.editor.contentHeight)

        adapter.editor.selectedRange = NSRange(location: 0, length: 0)
        try await settle()
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)
    }

    // MARK: - 글을 주고받는 약속

    @Test func typedTextReachesTheNoteFileThroughAutosave() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "저장", body: "처음"))

        type(" 그리고 더", into: adapter)
        try fixture.notes.flushPendingSaves()

        #expect(try fixture.fileText(id).hasSuffix("처음 그리고 더"))
    }

    /// 이 앱이 한 저장의 알림은 편집기로 돌아오지 않는다: 되돌리기 기록이 남고 커서가 제자리에 있다.
    @Test func ownSavesDoNotEchoIntoTheEditor() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "메아리", body: "처음"))
        var notified: [String] = []
        let forward = adapter.onTextChange
        adapter.onTextChange = { notified.append($0); forward?($0) }

        type("!", into: adapter)
        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        try fixture.notes.flushPendingSaves()
        fixture.notePanels.setColor(PaletteID(rawValue: "tint-2"), for: id)
        try fixture.notes.update(id) { $0.title = "다른 기능이 고친 제목" }

        #expect(notified == ["처음!"])
        #expect(adapter.editor.undoManager.canUndo)
        #expect(adapter.editor.selectedRange == NSRange(location: 1, length: 0))
        #expect(adapter.text == "처음!")
    }

    /// 편집기는 줄바꿈을 `\n`으로 고쳐 보인다. 그것만으로는 알리지 않고, 파일도 그대로다.
    @Test func normalisingLineEndingsIsNotReportedAsAnEdit() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "줄바꿈", body: "A\r\nB"))
        var notified: [String] = []
        adapter.onTextChange = { notified.append($0) }

        #expect(adapter.text == "A\nB")
        try fixture.notes.flushPendingSaves()
        // 다른 프로그램이 제목만 고쳤다. 본문은 그대로이므로 편집기에 다시 넣지 않는다.
        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "줄바꿈", with: "밖에서 고친 제목") }
        try fixture.notes.refresh()

        #expect(notified.isEmpty)
        #expect(try fixture.fileText(id).hasSuffix("A\r\nB"))
    }

    /// 밖에서 다른 글이 들어오면 그 글로 바꾸고 되돌리기 기록을 비운다. 알리지 않는다.
    @Test func externalEditReplacesTheTextClearsUndoAndIsNotReported() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "바깥", body: "처음"))
        type("!", into: adapter)
        try fixture.notes.flushPendingSaves()
        #expect(adapter.editor.undoManager.canUndo)
        var notified: [String] = []
        adapter.onTextChange = { notified.append($0) }

        try fixture.rewriteOutside(id) { $0 + "\n다른 프로그램이 쓴 줄" }
        try fixture.notes.refresh()

        #expect(adapter.text == "처음!\n다른 프로그램이 쓴 줄")
        #expect(!adapter.editor.undoManager.canUndo)
        #expect(notified.isEmpty)
    }

    /// 한 차례 늦게 알리려던 옛 글이, 그사이 밖에서 들어온 글을 덮어쓰지 않는다.
    @Test func staleDelayedChangeIsDroppedWhenOutsideTextArrives() async throws {
        defer { fixture.cleanUp() }
        let (_, adapter) = try fixture.open(NoteDraft(title: "늦은 알림", body: "처음"))
        var notified: [String] = []
        adapter.onTextChange = { notified.append($0) }
        // 텍스트 뷰를 거치지 않은 변경: 편집기는 다음 메인 큐 차례에 알리려고 표시해 둔다.
        let storage = try #require(adapter.editor.textView.textStorage)
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: " 옛 글")

        adapter.text = "밖에서 온 글"
        // 미뤄 둔 알림이 돌 차례를 준다.
        try await Task.sleep(for: .milliseconds(50))
        adapter.flushPendingChange()

        #expect(notified.isEmpty)
        #expect(adapter.text == "밖에서 온 글")
    }

    /// 같은 글을 넣으면 아무것도 하지 않는다(되돌리기 기록, 커서 유지).
    @Test func assigningTheSameTextKeepsUndoAndSelection() throws {
        defer { fixture.cleanUp() }
        let (_, adapter) = try fixture.open(NoteDraft(title: "같은 글", body: "처음"))
        type("!", into: adapter)
        adapter.editor.selectedRange = NSRange(location: 2, length: 0)

        adapter.text = "처음!"

        #expect(adapter.editor.undoManager.canUndo)
        #expect(adapter.editor.selectedRange == NSRange(location: 2, length: 0))
    }

    // MARK: - 편집 메뉴와 단축키

    /// 편집 메뉴의 동작(실행 취소, 다시 실행, 모두 선택)은 첫 응답자인 편집기에 닿는다.
    /// 메뉴가 하듯 첫 응답자에서 시작해 응답자 사슬을 따라 보낸다. 클립보드는 건드리지 않는다.
    @Test func editMenuActionsReachTheEditorInsideThePanel() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "편집 메뉴", body: "처음"))
        let window = try #require(fixture.notePanels.window(for: id))
        #expect(window.makeFirstResponder(adapter.view))
        let undoManager = adapter.editor.undoManager
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        type(" 더한 글", into: adapter)
        undoManager.endUndoGrouping()
        #expect(adapter.text == "처음 더한 글")
        // 창의 실행 취소 기록이 아니라 편집기의 것이 쓰인다.
        #expect(window.firstResponder?.undoManager === undoManager)

        #expect(window.firstResponder?.tryToPerform(Selector(("undo:")), with: nil) == true)
        #expect(adapter.text == "처음")
        #expect(window.firstResponder?.tryToPerform(Selector(("redo:")), with: nil) == true)
        #expect(adapter.text == "처음 더한 글")
        #expect(window.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil) == true)
        #expect(adapter.editor.selectedRange == NSRange(location: 0, length: 7))
        for action in [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:))] {
            #expect(adapter.view.responds(to: action))
        }
        // 되돌린 글도 저장소에 간다.
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.fileText(id).hasSuffix("처음 더한 글"))
    }

    /// 편집기의 단축키(spec 13 "편집")는 노트 창에 온 키 이벤트로 편집기가 직접 받는다. 앱 메뉴보다 앞선다.
    @Test func editorShortcutsWorkThroughThePanelsKeyEquivalentPath() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "단축키", body: "굵게"))
        let window = try #require(fixture.notePanels.window(for: id))
        #expect(window.makeFirstResponder(adapter.view))
        adapter.editor.selectedRange = NSRange(location: 0, length: 2)
        func press(_ chord: KeyChord) throws -> Bool {
            let characters = chord.key.menuKeyEquivalent
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: chord.modifiers.eventFlags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: chord.key.keyCode
            ))
            return window.performKeyEquivalent(with: event)
        }

        #expect(try press(KeyChord(.b, .command)))
        #expect(adapter.text == "**굵게**")
        #expect(try press(KeyChord(.nine, [.shift, .command])))
        #expect(adapter.text == "[ ] **굵게**")
        // 노트 창의 단축키(⌘N 등)는 편집기가 받지 않고 앱 메뉴로 넘어간다.
        #expect(try !press(KeyChord(.n, .command)))
    }

    // MARK: - 닫기 직전의 글

    /// 편집기가 아직 알리지 않은 글이 있어도, 창을 닫으면 그 글까지 파일에 쓰인다.
    @Test func closingTheWindowWritesTextTheEditorHadNotReportedYet() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "닫기", body: "처음"))
        // 텍스트 뷰를 거치지 않고 저장소만 바꾼다: `textDidChange`가 오지 않아 알림이 다음 차례로 미뤄진다.
        let storage = try #require(adapter.editor.textView.textStorage)
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: " 닫기 직전에 쓴 글")

        fixture.notePanels.closeWindow(id)

        #expect(fixture.notePanels.openNoteIDs.isEmpty)
        #expect(try fixture.fileText(id).hasSuffix("처음 닫기 직전에 쓴 글"))
    }

    @Test func trashAndQuitAlsoCollectUnreportedText() throws {
        defer { fixture.cleanUp() }
        let (trashed, first) = try fixture.open(NoteDraft(title: "휴지통", body: "가"))
        let (kept, second) = try fixture.open(NoteDraft(title: "끝내기", body: "나"))
        for adapter in [first, second] {
            let storage = try #require(adapter.editor.textView.textStorage)
            storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: " 마지막 글")
        }

        fixture.notePanels.moveToTrash(trashed)
        // 끝낼 때 App이 하는 차례.
        fixture.notePanels.flushPendingEdits()
        try fixture.notes.flushPendingSaves()

        let trashFile = fixture.location.trashDirectory.appendingPathComponent("\(trashed.rawValue).md")
        #expect(try String(contentsOf: trashFile, encoding: .utf8).hasSuffix("가 마지막 글"))
        #expect(try fixture.fileText(kept).hasSuffix("나 마지막 글"))
    }

    // MARK: - 접힘

    @Test func foldsArePersistedInWindowStateAndRestoredOnReopen() throws {
        defer { fixture.cleanUp() }
        let body = "> 토글\n\t안쪽 하나\n\t안쪽 둘\n마지막 줄"
        let (id, adapter) = try fixture.open(NoteDraft(title: "접힘", body: body))
        #expect(try fixture.storedFolds(for: id) == nil)

        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        adapter.editor.perform(.fold)
        #expect(adapter.editor.foldedLines == [0])
        #expect(try fixture.storedFolds(for: id) == [0])
        // 접힘은 노트 파일에 적지 않는다(D-018).
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.fileText(id).hasSuffix(body))

        fixture.notePanels.closeWindow(id)
        #expect(try fixture.storedFolds(for: id) == [0])
        try fixture.notePanels.open(id, focus: false)
        let reopened = try #require(fixture.editors.editor(for: id))
        #expect(reopened !== adapter)
        #expect(reopened.editor.foldedLines == [0])

        reopened.editor.perform(.unfold)
        #expect(try fixture.storedFolds(for: id) == nil)
    }

    /// 다른 프로그램이 접힌 토글 위에 줄을 더하면 접힘이 그 토글을 따라간다. 토글이 없어지면 접힘도 없어진다.
    @Test func externalEditKeepsFoldsOnTheSameToggle() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "바깥", body: "첫 줄\n> 토글\n\t안쪽\n끝"))
        adapter.editor.selectedRange = NSRange(location: 6, length: 0)
        adapter.editor.perform(.fold)
        #expect(adapter.editor.foldedLines == [1])

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "첫 줄\n", with: "첫 줄\n새로 낀 줄\n") }
        try fixture.notes.refresh()
        #expect(adapter.text == "첫 줄\n새로 낀 줄\n> 토글\n\t안쪽\n끝")
        #expect(adapter.editor.foldedLines == [2])
        #expect(try fixture.storedFolds(for: id) == [2])

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "> 토글", with: "토글 아님") }
        try fixture.notes.refresh()
        #expect(adapter.editor.foldedLines.isEmpty)
        #expect(try fixture.storedFolds(for: id) == nil)
    }

    // MARK: - 표시 방식

    @Test func checkboxStyleComesFromTheDisplayOptionAndUpdatesLiveEditors() throws {
        defer { fixture.cleanUp() }
        let (_, adapter) = try fixture.open(NoteDraft(title: "체크", body: "[ ] 할 일"))
        #expect(fixture.editors.options.checkbox == .box)
        #expect(adapter.editor.configuration.checkboxStyle == .box)

        fixture.editors.options.checkbox = .bracket

        #expect(adapter.editor.configuration.checkboxStyle == .bracket)
        let (_, later) = try fixture.open(NoteDraft(title: "나중", body: "[ ] 할 일"))
        #expect(later.editor.configuration.checkboxStyle == .bracket)
    }
}
