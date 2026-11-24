import AppKit
@_spi(Verification) import Editor
import Models
@testable import NotePanel
import Store
import Scheduling
import Reminders
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

    @Test func fixedHeightBlankAreaBelongsToTheTextView() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "빈 영역", body: "첫 줄"))
        let root = try #require(fixture.notePanels.window(for: id)?.contentView)
        root.layoutSubtreeIfNeeded()
        let view = adapter.editor.textView
        let clip = try #require(view.enclosingScrollView?.contentView)
        let point = NSPoint(x: clip.bounds.midX, y: clip.bounds.maxY - 10)
        let hit = root.hitTest(clip.convert(point, to: root.superview))
        #expect(hit === view)
        #expect(view.characterIndexForInsertion(at: view.convert(point, from: clip)) == view.string.utf16.count)
    }

    @Test(arguments: [NoteDisplayOptions.FormatBar.hidden, .editing])
    func returningToAnOpenNoteKeepsItsOwnCaretAndScroll(formatBar: NoteDisplayOptions.FormatBar) throws {
        defer { fixture.cleanUp() }
        let panels = fixture.notePanels
        panels.displayOptions.formatBar = formatBar
        let body = (0..<50).map { "본문 줄 \($0)" }.joined(separator: "\n")
        let (id, adapter) = try fixture.open(NoteDraft(title: "이어 쓰기", body: body))
        let (other, _) = try fixture.open(NoteDraft(title: "다른 노트"))
        let window = try #require(panels.window(for: id))
        let scroll = try #require(adapter.view.enclosingScrollView)
        adapter.editor.forcesActiveAppearance = true
        _ = window.makeFirstResponder(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let caret = NSRange(location: 3, length: 0)
        adapter.editor.selectedRange = caret
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(clip)
        let origin = clip.bounds.origin
        #expect(origin.y > 0)
        func check() {
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(adapter.editor.selectedRange == caret)
            #expect(clip.bounds.origin == origin)
        }
        #expect(panels.returnKey(to: id))
        check()
        let otherWindow = panels.window(for: other)
        panels.isKeyPanel = { $0 === otherWindow }
        #expect(panels.focusNextNote() == id)
        check()
        panels.closeWindow(other)
        check()
    }

    @Test func documentViewSitsInThePanelsScrollViewAndTheWindowFollowsItsHeight() throws {
        defer { fixture.cleanUp() }
        fixture.notePanels.displayOptions.heightMode = .fitContent
        let (id, adapter) = try fixture.open(NoteDraft(title: "높이", body: "한 줄\n두 줄\n세 줄\n네 줄\n다섯 줄"))
        let window = try #require(fixture.notePanels.window(for: id))
        let theme = fixture.theme
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        let padding = theme.docPadding

        #expect(adapter.view.isFlipped)
        let scrollView = try #require(adapter.view.enclosingScrollView)
        #expect(scrollView.documentView === adapter.view)
        // 안쪽 여백은 편집기가 넣는다: 내용 높이는 줄 다섯과 위아래 여백이다.
        #expect(adapter.editor.contentHeight == theme.lineHeight(.body) * 5 + padding.top + padding.bottom)
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)

        window.contentView?.layoutSubtreeIfNeeded()
        #expect(scrollView.frame.height == adapter.editor.contentHeight)
        #expect(adapter.view.frame.width == scrollView.contentSize.width)
        #expect(adapter.view.frame.origin == .zero)
        #expect(scrollView.contentView.bounds.origin == .zero)
        // 내용이 다 보인다(스크롤할 것이 없다).
        #expect(adapter.view.frame.height <= scrollView.contentSize.height + 0.5)
    }

    @Test func fixedWindowKeepsTheCaretVisibleWhenTypingPastSixLines() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "고정"))
        let window = try #require(fixture.notePanels.window(for: id))
        let original = window.frame
        let scroll = try #require(adapter.view.enclosingScrollView)
        adapter.editor.forcesActiveAppearance = true
        #expect(window.makeFirstResponder(adapter.view))
        type((1...12).map(String.init).joined(separator: "\n"), into: adapter)
        window.contentView?.layoutSubtreeIfNeeded()
        let caret = try #require(adapter.editor.caretFrame)
        #expect(window.frame == original)
        #expect(scroll.documentVisibleRect.minY > 0)
        #expect(scroll.documentVisibleRect.contains(caret))
        let end = adapter.editor.selectedRange.location
        let savedY = scroll.documentVisibleRect.minY
        adapter.editor.selectedRange = NSRange(location: end - 1, length: 1)
        fixture.notePanels.closeWindow(id)
        try fixture.notePanels.open(id, focus: false)
        let restored = try #require(fixture.notePanels.controllers[id])
        let clip = try #require(restored.editor.view.enclosingScrollView?.contentView)
        var expected = clip.bounds
        expected.origin.y = savedY
        #expect(clip.bounds.minY == clip.constrainBoundsRect(expected).minY)
        #expect((restored.editor.view as? NSTextView)?.selectedRange() == NSRange(location: end, length: 0))
    }

    @Test func reopenedPositionClampsAfterExternalShortening() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "일정", body: (1...30).map(String.init).joined(separator: "\n")))
        adapter.editor.selectedRange = NSRange(location: adapter.text.utf16.count - 3, length: 3)
        adapter.editor.textView.scrollRangeToVisible(adapter.editor.selectedRange)
        fixture.notePanels.closeWindow(id)
        try fixture.notes.update(id) { $0.body = "짧음" }
        try fixture.notePanels.open(id, focus: false)
        let reopened = try #require(fixture.editors.editor(for: id))
        #expect(reopened.editor.selectedRange == NSRange(location: 2, length: 0))
        #expect(reopened.view.enclosingScrollView?.documentVisibleRect.minY == 0)
    }

    @Test func fixedHeightShowsEntireLinkFieldAtLastLine() throws {
        defer { fixture.cleanUp() }
        let body = (1...18).map { "본문 줄 \($0)" }.joined(separator: "\n")
        let (id, adapter) = try fixture.open(NoteDraft(title: "링크", body: body))
        let window = try #require(fixture.notePanels.window(for: id))
        let scroll = try #require(adapter.view.enclosingScrollView)
        let original = window.frame
        adapter.editor.forcesActiveAppearance = true
        adapter.editor.focus()
        let range = (body as NSString).range(of: "본문 줄 18")
        adapter.editor.selectedRange = range
        adapter.editor.textView.scrollRangeToVisible(range)
        let field = try #require(adapter.view.subviews.first { $0.subviews.contains { $0.accessibilityLabel() == "링크 주소" } })
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "l",
            charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37))
        #expect(adapter.view.performKeyEquivalent(with: key))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!field.isHidden && window.frame == original)
        #expect(scroll.documentVisibleRect.contains(field.frame))
        adapter.editor.commitLink("https://example.com")
        fixture.notePanels.beginTitleEditing(for: id)
        #expect(window.firstResponder !== adapter.view)
        #expect(!adapter.view.performKeyEquivalent(with: key))
        #expect(field.isHidden)
    }

    @Test func typingGrowsTheWindowFromTheSameTopEdge() async throws {
        defer { fixture.cleanUp() }
        fixture.notePanels.displayOptions.heightMode = .fitContent
        let (id, adapter) = try fixture.open(NoteDraft(title: "늘어남", body: "하나\n둘\n셋\n넷"))
        let window = try #require(fixture.notePanels.window(for: id))
        let top = window.frame.maxY
        let before = window.frame.height

        type("\n다섯\n여섯", into: adapter)
        let target = before + fixture.theme.lineHeight(.body) * 2
        // 병렬 시험의 메인 액터 대기 시간과 무관하게 이 창이 예약한 마지막 전환까지 확인한다.
        while let animation = fixture.notePanels.controllers[id]?.heightAnimation { await animation.value }

        #expect(window.frame.height == target)
        #expect(window.frame.maxY == top)
    }

    /// 기호는 커서가 있는 줄에서도 보이지 않으므로(D-036) 커서가 링크 줄에 들어가도 창 높이는 그대로다.
    /// 그 줄에 글자를 쳐 줄이 넘어가면 창 높이가 내용을 끝까지 따라간다. 본문이 스크롤되지 않는다.
    @Test func windowKeepsItsHeightUnderTheCaretAndFollowsTypingOnALinkLine() async throws {
        defer { fixture.cleanUp() }
        fixture.notePanels.displayOptions.heightMode = .fitContent
        fixture.notePanels.displayOptions.formatBar = .editing
        // 본문 영역의 가장 낮은 높이(네 줄)보다 길어야 창 높이가 내용을 그대로 따른다.
        let body = "## 아이디어\n하나\n둘\n셋\n+ 참고 링크\n\t- [PR #482 포커스 투명도](https://github.com/example/floating-notes/pull/482)"
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
        #expect(window.frame.height == closed)
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)

        type(String(repeating: "가나다라마바사 ", count: 6), into: adapter)
        try await settle()
        #expect(window.frame.height > closed)
        #expect(window.frame.height == chrome + adapter.editor.contentHeight)
        let toolbarHeight = fixture.theme.shape(.chromeHeight)
        #expect(scrollView.contentView.bounds.origin == CGPoint(x: 0, y: toolbarHeight))
        #expect(scrollView.frame.height + toolbarHeight == adapter.editor.contentHeight)

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

    /// 밖에서 다른 글이 들어오면(끝에 덧붙인 것이 아닌 바꿈) 그 글로 바꾸고 되돌리기 기록을 비운다. 알리지 않는다.
    @Test func externalEditReplacesTheTextClearsUndoAndIsNotReported() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "바깥", body: "처음"))
        type("!", into: adapter)
        try fixture.notes.flushPendingSaves()
        #expect(adapter.editor.undoManager.canUndo)
        var notified: [String] = []
        adapter.onTextChange = { notified.append($0) }

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "처음!", with: "다른 프로그램이 고친 글") }
        try fixture.notes.refresh()

        #expect(adapter.text == "다른 프로그램이 고친 글")
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

        #expect(window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) == true)
        #expect(adapter.text == "처음")
        #expect(window.firstResponder?.tryToPerform(NSSelectorFromString("redo:"), with: nil) == true)
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

        // 키 창이 아닌 노트의 편집기는 키를 받지 않는다(보고 있지 않은 노트의 글이 바뀌지 않게).
        #expect(!window.isKeyWindow)
        #expect(try !press(KeyChord(.b, .command)))
        #expect(adapter.text == "굵게")
        // 시험에서는 실제 키 창을 만들지 않는다. 편집 중인 것으로 보게 하고 같은 길로 넣는다.
        adapter.editor.forcesActiveAppearance = true
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
        let body = "+ 토글\n\t안쪽 하나\n\t안쪽 둘\n마지막 줄"
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
        let (id, adapter) = try fixture.open(NoteDraft(title: "바깥", body: "첫 줄\n+ 토글\n\t안쪽\n끝"))
        adapter.editor.selectedRange = NSRange(location: 6, length: 0)
        adapter.editor.perform(.fold)
        #expect(adapter.editor.foldedLines == [1])

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "첫 줄\n", with: "첫 줄\n새로 낀 줄\n") }
        try fixture.notes.refresh()
        #expect(adapter.text == "첫 줄\n새로 낀 줄\n+ 토글\n\t안쪽\n끝")
        #expect(adapter.editor.foldedLines == [2])
        #expect(try fixture.storedFolds(for: id) == [2])

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "+ 토글", with: "토글 아님") }
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

    @Test func inlineCodeStyleComesFromTheDisplayOptionAndUpdatesLiveEditors() throws {
        defer { fixture.cleanUp() }
        let (_, adapter) = try fixture.open(NoteDraft(title: "코드", body: "앞 `코드` 뒤"))
        // 기본값은 `tokens.json`의 `display.defaults`와 같다.
        let tokens = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: ThemeResources.tokensURL())) as? [String: Any])
        let display = try #require(tokens["display"] as? [String: Any])
        #expect(NoteEditorOptions().inlineCode.rawValue == (display["defaults"] as? [String: String])?["inline-code"])
        #expect(InlineCodeStyle.allCases.map(\.rawValue) == display["inline-code"] as? [String])
        #expect(adapter.editor.configuration.inlineCodeStyle == .accent)

        fixture.editors.options.inlineCode = .plain

        #expect(adapter.editor.configuration.inlineCodeStyle == .plain)
        let (_, later) = try fixture.open(NoteDraft(title: "나중", body: "`코드`"))
        #expect(later.editor.configuration.inlineCodeStyle == .plain)
        fixture.editors.options.inlineCode = .accent
        #expect(adapter.editor.configuration.inlineCodeStyle == .accent)
        #expect(later.editor.configuration.inlineCodeStyle == .accent)
    }

    // MARK: - 창 높이(D-031)

    /// 사용자가 본 문제: 여러 줄인 노트가 두 줄쯤의 높이에 머물고 그 안에서 스크롤됐다. Markdown 편집기를
    /// 끼운 창이 열두 줄 노트를 처음부터 내용 높이로 띄우고, 스크롤할 것이 없는지 본다.
    @Test func aTwelveLineNoteOpensAtItsFullHeightWithNothingToScroll() throws {
        defer { fixture.cleanUp() }
        fixture.notePanels.displayOptions.heightMode = .fitContent
        let body = (1...12).map { "\($0)번째 줄" }.joined(separator: "\n")
        let (id, adapter) = try fixture.open(NoteDraft(title: "열두 줄", body: body))
        let window = try #require(fixture.notePanels.window(for: id))
        let theme = fixture.theme
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        let content = theme.lineHeight(.body) * 12 + theme.docPadding.top + theme.docPadding.bottom
        window.contentView?.layoutSubtreeIfNeeded()
        let scrollView = try #require(adapter.view.enclosingScrollView)

        #expect(adapter.editor.contentHeight == content)
        #expect(window.frame.height == chrome + content)
        // 본문 영역이 창을 따라 커졌고, 문서 높이가 보이는 높이와 같다.
        #expect(scrollView.frame.height == content)
        #expect(adapter.view.frame.height == scrollView.documentVisibleRect.height)
        #expect(scrollView.documentVisibleRect.origin == .zero)
        // 스크롤 막대가 보이지 않는다.
        #expect(scrollView.verticalScroller?.isHidden != false)
    }

    /// 한두 줄 노트와 빈 노트는 본문 네 줄만큼의 높이로 뜨고, 본문 뷰가 그 영역을 채운다.
    @Test(arguments: ["", "한 줄", "한 줄\n두 줄"])
    func shortNotesOpenFourBodyLinesTall(body: String) throws {
        defer { fixture.cleanUp() }
        fixture.notePanels.displayOptions.heightMode = .fitContent
        let (id, adapter) = try fixture.open(NoteDraft(title: "짧은 노트", body: body))
        let window = try #require(fixture.notePanels.window(for: id))
        let theme = fixture.theme
        let chrome = theme.shape(.chromeHeight) + theme.shape(.borderWidth)
        let minimum = theme.lineHeight(.body) * 4 + theme.docPadding.top + theme.docPadding.bottom
        window.contentView?.layoutSubtreeIfNeeded()
        let scrollView = try #require(adapter.view.enclosingScrollView)

        #expect(window.frame.height == chrome + minimum)
        #expect(scrollView.frame.height == minimum)
        // 글 아래의 빈 자리를 눌러도 본문이 받는다.
        #expect(adapter.view.frame.height == scrollView.contentSize.height)
        #expect(scrollView.contentView.bounds.origin == .zero)
    }

    // MARK: - 창이 닫힌 사이에 바뀐 파일과 접힘

    /// 검토에서 나온 문제: 둘째 줄의 토글을 접고 창을 닫은 뒤 다른 프로그램이 맨 위에 두 줄을 넣으면,
    /// 다시 열 때 줄 번호만 보고 엉뚱한 토글을 접었다.
    @Test func foldsFollowTheirToggleWhenTheFileChangedWhileTheWindowWasClosed() throws {
        defer { fixture.cleanUp() }
        let body = "머리말\n+ 첫 토글\n\t안\n+ 접어 둔 토글\n\t안\n+ 셋째 토글\n\t안"
        let (id, adapter) = try fixture.open(NoteDraft(title: "닫힌 사이", body: body))
        adapter.editor.selectedRange = NSRange(location: (body as NSString).range(of: "접어 둔").location, length: 0)
        adapter.editor.perform(.fold)
        #expect(adapter.editor.foldedLines == [3])
        fixture.notePanels.closeWindow(id)
        #expect(try fixture.storedFolds(for: id) == [3])

        try fixture.rewriteOutside(id) { $0.replacingOccurrences(of: "머리말\n", with: "새 줄 하나\n새 줄 둘\n머리말\n") }
        try fixture.notes.refresh()
        try fixture.notePanels.open(id, focus: false)

        let reopened = try #require(fixture.editors.editor(for: id))
        #expect(reopened.text.hasPrefix("새 줄 하나\n새 줄 둘\n머리말\n"))
        // 같은 토글("접어 둔 토글")이 접혀 있다. 줄 번호 3의 토글("첫 토글")이 아니다.
        #expect(reopened.editor.foldedLines == [5])
        #expect(try fixture.storedFolds(for: id) == [5])
    }

    /// 닫힌 노트의 끝에 줄이 붙어도(빠른 캡처) 접힘은 그대로다. 접힌 토글이 없어졌으면 접힘도 버린다.
    @Test func foldsSurviveLinesAppendedWhileClosedAndAreDroppedWhenTheirToggleIsGone() throws {
        defer { fixture.cleanUp() }
        let body = "+ 토글\n\t안\n끝"
        let (id, adapter) = try fixture.open(NoteDraft(title: "덧붙임", body: body))
        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        adapter.editor.perform(.fold)
        fixture.notePanels.closeWindow(id)

        try fixture.notes.update(id) { $0.body += "\n- [ ] 캡처한 줄\n+ 새 토글\n\t안" }
        try fixture.notePanels.open(id, focus: false)
        #expect(fixture.editors.editor(for: id)?.editor.foldedLines == [0])
        fixture.notePanels.closeWindow(id)

        try fixture.notes.update(id) { $0.body = "다른 줄\n+ 새 토글\n\t안" }
        try fixture.notePanels.open(id, focus: false)
        #expect(fixture.editors.editor(for: id)?.editor.foldedLines.isEmpty == true)
        #expect(try fixture.storedFolds(for: id) == nil)
    }

    /// 접힌 토글 줄의 글을 고치면 적어 둔 글도 따라 바뀐다. 낡은 글이 남으면 다시 열 때 접힘을 잃는다.
    @Test func editingAFoldedToggleLineKeepsItsFoldAcrossReopen() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "토글 고침", body: "+ 토글\n\t안\n끝"))
        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        adapter.editor.perform(.fold)
        let view = adapter.editor.textView
        view.insertText(" 고친 이름", replacementRange: NSRange(location: 4, length: 0))
        #expect(adapter.text == "+ 토글 고친 이름\n\t안\n끝")
        #expect(adapter.editor.foldedLines == [0])

        fixture.notePanels.closeWindow(id)
        try fixture.notePanels.open(id, focus: false)

        #expect(fixture.editors.editor(for: id)?.editor.foldedLines == [0])
    }

    // MARK: - 이 앱의 다른 곳이 덧붙인 글(빠른 캡처)

    /// 떠 있는 노트에 다른 곳이 한 줄을 덧붙이면 편집기가 그 줄을 받고, 커서와 되돌리기 기록과 접힘이
    /// 그대로다. 이어서 친 글과 덧붙인 줄이 모두 파일에 남는다.
    @Test func lineAppendedByAnotherWriterKeepsCaretUndoAndFoldsAndSurvivesTyping() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "캡처", body: "+ 토글\n\t안\n끝"))
        adapter.editor.selectedRange = NSRange(location: 1, length: 0)
        adapter.editor.perform(.fold)
        type("!", into: adapter)
        try fixture.notes.flushPendingSaves()
        let caret = adapter.editor.selectedRange
        var notified: [String] = []
        let forward = adapter.onTextChange
        adapter.onTextChange = { notified.append($0); forward?($0) }

        try fixture.notes.update(id) { $0.body += "\n- [ ] 캡처한 줄" }

        #expect(adapter.text == "+ 토글\n\t안\n끝!\n- [ ] 캡처한 줄")
        #expect(adapter.editor.selectedRange == caret)
        #expect(adapter.editor.undoManager.canUndo)
        #expect(adapter.editor.foldedLines == [0])
        #expect(notified.isEmpty)

        let view = adapter.editor.textView
        view.insertText("?", replacementRange: view.selectedRange())
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.fileText(id).hasSuffix("+ 토글\n\t안\n끝!?\n- [ ] 캡처한 줄"))
        #expect(try fixture.storedFolds(for: id) == [0])
    }

    /// 끝에 붙기만 한 것이 아닌 변경(끝의 빈 줄을 다듬고 붙임)도 달라진 부분만 넣는다: 되돌리기 기록이 남고,
    /// 빈 마지막 줄의 커서는 바깥이 쓴 줄 속이 아니라 그 뒤에 놓여, 이어 친 글이 그 줄에 끼어들지 않는다.
    @Test func outsideChangeThatIsNotAnAppendKeepsUndoAndTheCaretOutOfTheForeignLine() throws {
        defer { fixture.cleanUp() }
        let (_, adapter) = try fixture.open(NoteDraft(title: "캡처", body: "첫 줄\n둘째 줄\n\n"))
        let view = adapter.editor.textView
        adapter.editor.selectedRange = NSRange(location: 3, length: 0)
        view.insertText("!", replacementRange: view.selectedRange())
        adapter.editor.selectedRange = NSRange(location: (adapter.text as NSString).length, length: 0)
        var notified: [String] = []
        let forward = adapter.onTextChange
        adapter.onTextChange = { notified.append($0); forward?($0) }

        adapter.applyOutsideChange(to: "첫 줄!\n둘째 줄\n[ ] 우유\n")

        #expect(adapter.text == "첫 줄!\n둘째 줄\n[ ] 우유\n")
        #expect(adapter.editor.selectedRange == NSRange(location: (adapter.text as NSString).length, length: 0))
        #expect(adapter.editor.undoManager.canUndo)
        #expect(notified.isEmpty)
        view.insertText("이어서", replacementRange: view.selectedRange())
        #expect(adapter.text == "첫 줄!\n둘째 줄\n[ ] 우유\n이어서")
    }

    /// 한글을 조합하는 중에 덧붙여도 조합이 끊기지 않고, 조합한 글자와 덧붙인 줄이 모두 저장된다.
    @Test func appendWhileComposingKeepsTheCompositionAndSavesBoth() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "조합", body: "처음"))
        let view = adapter.editor.textView
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
        #expect(view.hasMarkedText())

        try fixture.notes.update(id) { $0.body += "\n캡처" }

        #expect(view.hasMarkedText())
        #expect(adapter.text == "처음ㅎ\n캡처")
        view.insertText("한", replacementRange: view.markedRange())
        #expect(!view.hasMarkedText())
        try fixture.notes.flushPendingSaves()
        #expect(try fixture.fileText(id).hasSuffix("처음한\n캡처"))
        #expect(view.string == "처음한\n캡처")
    }
}

extension MarkdownBodyEditorTests {
    @Test(arguments: [false, true], [false, true])
    func registerSameLineAfterDeletion(externally: Bool, dismissed: Bool) async throws {
        defer { fixture.cleanUp() }
        let bridge = FakeCalendarBridge()
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { bridge })
        try service.start()
        defer { service.stop() }
        let writer = InlineScheduleWriter(notes: fixture.notes, service: service)
        fixture.editors.onAcceptDate = { id, request in try writer.accept(request, in: id) }
        let (id, adapter) = try fixture.open(NoteDraft(title: "등록", body: "회의"))
        adapter.editor.forcesActiveAppearance = true
        adapter.focus()
        func accept() async throws -> String {
            if adapter.text == "회의" { type(" 내일 3시~4시", into: adapter) }
            #expect(adapter.editor.textView.accessibilityHelp()?.contains("일정") == true)
            adapter.editor.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
            adapter.flushPendingChange()
            await service.flush()
            #expect(adapter.text == "회의")
            let items = try fixture.notes.load(id).schedules
            #expect(items.count == 1)
            return try #require(items.first?.id)
        }
        let first = try await accept()
        if dismissed {
            type(" 내일 3시~4시", into: adapter)
            adapter.editor.textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            #expect(adapter.editor.textView.accessibilityHelp() == nil)
            adapter.flushPendingChange()
        }
        if externally {
            bridge.deleteExternally(first)
        } else {
            let clock = try ReminderEditorModel(noteID: id, notes: fixture.notes)
            clock.select(first)
            #expect(clock.remove())
        }
        await service.flush()
        #expect(try fixture.notes.load(id).schedules.isEmpty)
        let second = try await accept()
        #expect(first != second)
        #expect(Set(bridge.items.keys) == [second])
    }

    @Test(arguments: ["", "첫 줄"])
    func backtabAtStartFocusesTitle(body: String) throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "제목", body: body))
        adapter.focus()
        adapter.editor.selectedRange = NSRange(location: 0, length: 0)
        adapter.editor.textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        let window = try #require(fixture.notePanels.window(for: id))
        let title = try #require(window.firstResponder as? NSTextView)
        #expect(title !== adapter.editor.textView)
        #expect(title.string == "제목")
        #expect(adapter.text == body)
        title.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(window.firstResponder === adapter.editor.textView)
    }
}

extension MarkdownBodyEditorTests {
    @Test func windowDispatchesBoldForSelectionAndTypingState() throws {
        defer { fixture.cleanUp() }
        let (id, adapter) = try fixture.open(NoteDraft(title: "서식", body: "한글"))
        let window = try #require(fixture.notePanels.window(for: id))
        let editor = adapter.editor
        editor.forcesActiveAppearance = true
        adapter.focus()
        let menu = MainMenu.make(appName: "Float", table: .standard, dispatcher: fixture.commands)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "ㅠ",
            charactersIgnoringModifiers: "ㅠ", isARepeat: false, keyCode: 11))
        func pressBold() {
            let handled = window.performKeyEquivalent(with: event) || menu.performKeyEquivalent(with: event)
            #expect(handled)
        }
        editor.selectedRange = NSRange(location: 0, length: 2)
        pressBold()
        #expect(adapter.text == "**한글**")
        pressBold()
        #expect(adapter.text == "한글")
        editor.selectedRange = NSRange(location: 2, length: 0)
        pressBold()
        #expect(adapter.text == "한글" && editor.formattingState.bold)
        #expect(editor.selectedRange == NSRange(location: 2, length: 0))
        pressBold()
        #expect(adapter.text == "한글" && !editor.formattingState.bold)
        pressBold()
        editor.textView.insertText("가", replacementRange: editor.selectedRange)
        #expect(adapter.text == "한글**가**")
    }
}
