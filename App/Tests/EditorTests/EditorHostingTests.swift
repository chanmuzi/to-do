import AppKit
import Testing
import Theme
@testable import Editor

/// 편집기를 바깥의 스크롤 뷰(노트 창)에 넣어 쓸 때 필요한 것: 스크롤 뷰 없는 본문 뷰, 미뤄 둔 알림을 지금
/// 내놓기, 겹쳐 뜬 다른 뷰 위에서 I자 커서를 넣지 않기.
@MainActor
@Suite struct EditorHostingTests {
    /// 바깥 스크롤 뷰에 편집기의 본문 뷰를 넣고, 그 위 오른쪽 아래에 버튼 같은 뷰를 겹친 창.
    @MainActor private struct Host {
        let window: NSWindow
        let editor: MarkdownEditor
        let scrollView = NSScrollView()
        let overlay = NSView(frame: NSRect(x: 280, y: 0, width: 40, height: 20))

        init(_ text: String) throws {
            editor = MarkdownEditor(theme: try Theme.bundled())
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), styleMask: [.borderless],
                backing: .buffered, defer: true
            )
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
            scrollView.frame = root.bounds
            scrollView.documentView = editor.documentView
            editor.documentView.setFrameSize(NSSize(width: 340, height: editor.documentView.frame.height))
            root.addSubview(scrollView)
            root.addSubview(overlay)
            window.contentView = root
            editor.text = text
        }

        func mouseMoved(atWindowPoint point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
        }
    }

    @Test func documentViewIsAFlippedBodyThatCarriesThePaddingAndReportsItsHeight() throws {
        let host = try Host("한 줄\n너비가 줄면 다음 줄로 넘어가는 긴 줄")
        let theme = try Theme.bundled()
        var heights: [CGFloat] = []
        host.editor.onContentHeightChange = { heights.append($0) }

        #expect(host.editor.documentView.isFlipped)
        #expect(host.editor.documentView.enclosingScrollView === host.scrollView)
        let expected = theme.lineHeight(.body) * 2 + theme.docPadding.top + theme.docPadding.bottom
        #expect(host.editor.contentHeight == expected)
        // 너비가 바뀌면 줄바꿈이 달라져 높이를 다시 알린다.
        host.editor.documentView.setFrameSize(NSSize(width: 60, height: 0))
        #expect((heights.last ?? 0) > expected)
    }

    @Test func pendingChangeIsReportedImmediatelyWhenAsked() throws {
        let host = try Host("처음")
        var changes: [String] = []
        host.editor.onTextChange = { changes.append($0) }
        let storage = try #require(host.editor.controller.textView.textStorage)

        // 알릴 것이 없으면 아무것도 하지 않는다.
        host.editor.flushPendingChange()
        #expect(changes.isEmpty)
        // 텍스트 뷰의 알림(`textDidChange`)을 거치지 않은 변경은 다음 메인 큐 차례까지 미뤄진다.
        storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: " 그리고")
        #expect(changes.isEmpty)
        host.editor.flushPendingChange()
        host.editor.flushPendingChange()

        #expect(changes == ["처음 그리고"])
    }

    /// 커서가 들어간 줄은 감췄던 기호(링크의 주소)가 보여 줄이 넘어간다. 글이 바뀌지 않아도 높이를 알리고,
    /// 커서가 나가면 줄어든 높이를 다시 알린다. 알리지 않으면 창 높이가 내용과 어긋난다.
    @Test func heightIsReportedWhenTheCaretLineRevealsOrHidesItsMarkers() async throws {
        let h = try EditorHarness("첫 줄\n- [링크 글자](https://example.com/a/very/long/address/that/wraps/onto/another/line)")
        h.caret(atEndOfLine: 0)
        try await Task.sleep(for: .milliseconds(30))
        let folded = h.editor.contentHeight

        h.caret(atEndOfLine: 1)
        try await Task.sleep(for: .milliseconds(30))
        let revealed = h.editor.contentHeight
        #expect(revealed > folded)
        #expect(h.heights.last == revealed)

        h.caret(atEndOfLine: 0)
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.editor.contentHeight == folded)
        #expect(h.heights.last == folded)
    }

    /// 커서 줄에서 드러난 주소 뒤에 글자를 치면 그 줄이 높아진다(작은 글자 줄에 본문 글자가 들어감).
    /// 그 높이도 알려야 한다.
    @Test func heightFollowsTypingOnARevealedWrappedLine() async throws {
        let h = try EditorHarness(
            "## 아이디어\n> 참고 링크\n\t- [PR #482 포커스 투명도](https://github.com/example/floating-notes/pull/482)"
        )
        h.caret(atEndOfLine: 2)
        try await Task.sleep(for: .milliseconds(30))
        h.type("가나")
        let immediate = h.heights.last
        try await Task.sleep(for: .milliseconds(30))

        #expect(immediate == h.editor.contentHeight)
        #expect(h.heights.last == h.editor.contentHeight)
    }

    /// 넣을 때는 미뤄 둔 옛 알림을 버린다. 그 뒤에 내놓으라고 해도 옛 글이 나오지 않는다.
    @Test func assigningTextDiscardsThePendingChange() throws {
        let host = try Host("처음")
        var changes: [String] = []
        host.editor.onTextChange = { changes.append($0) }
        let storage = try #require(host.editor.controller.textView.textStorage)
        storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: " 옛 글")

        host.editor.text = "밖에서 온 글"
        host.editor.flushPendingChange()

        #expect(changes.isEmpty)
        #expect(host.editor.text == "밖에서 온 글")
    }

    /// 겹쳐 뜬 뷰가 마우스를 받는 자리에서는 글자 칸이 아니다(규칙 9).
    @Test func textViewIsNotTheHitViewUnderAnOverlappingView() throws {
        let host = try Host("글자가 있는 줄\n둘째 줄")
        let view = host.editor.controller.textView

        // 글자 위(창 좌표는 왼쪽 아래가 원점).
        #expect(view.isHitView(for: try host.mouseMoved(atWindowPoint: NSPoint(x: 40, y: 180))))
        // 겹친 뷰 위.
        #expect(!view.isHitView(for: try host.mouseMoved(atWindowPoint: NSPoint(x: 300, y: 10))))
        // 편집기 안의 뷰(코드 블록 복사 버튼)는 편집기의 것으로 친다.
        host.editor.controller.copyButton.frame = NSRect(x: 100, y: 30, width: 20, height: 20)
        host.editor.controller.copyButton.isHidden = false
        let inside = view.convert(NSPoint(x: 110, y: 40), to: nil)
        #expect(view.isHitView(for: try host.mouseMoved(atWindowPoint: inside)))
    }

    @Test func movingOverAnOverlappingViewClearsLinkHoverAndSetsNoIBeam() throws {
        let host = try Host("[링크](https://example.com) 뒤의 글자")
        let view = host.editor.controller.textView
        let controller = host.editor.controller
        let linkPoint = try #require(controller.textPoint(forLine: 0))
        view.mouseMoved(with: try host.mouseMoved(atWindowPoint: view.convert(linkPoint, to: nil)))
        #expect(controller.hoveredLink != nil)

        NSCursor.iBeam.set()
        view.mouseMoved(with: try host.mouseMoved(atWindowPoint: NSPoint(x: 300, y: 10)))

        #expect(controller.hoveredLink == nil)
        #expect(NSCursor.current == NSCursor.arrow)
    }
}
