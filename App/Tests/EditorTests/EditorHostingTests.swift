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

    /// 기호는 커서가 있는 줄에서도 보이지 않는다. 커서가 링크 줄에 드나들어도 줄이 넘어가지 않고
    /// 높이도 그대로다(D-036. 예전에는 감췄던 주소가 드러나 줄이 넘어갔다).
    @Test func heightStaysWhenTheCaretEntersALineWithHiddenMarkers() async throws {
        let h = try EditorHarness("첫 줄\n- [링크 글자](https://example.com/a/very/long/address/that/wraps/onto/another/line)")
        h.caret(atEndOfLine: 0)
        try await Task.sleep(for: .milliseconds(30))
        let height = h.editor.contentHeight
        let reported = h.heights.count
        let padding = h.theme.docPadding
        #expect(height == padding.top + padding.bottom + h.theme.lineHeight(.body) * 2)

        h.caret(atEndOfLine: 1)
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.editor.contentHeight == height)
        #expect(h.heights.count == reported)
    }

    /// 링크 줄 끝에 글자를 쳐도 높이를 곧바로 알린다.
    @Test func heightFollowsTypingOnALinkLine() async throws {
        let h = try EditorHarness(
            "## 아이디어\n> 참고 링크\n\t- [PR #482 포커스 투명도](https://github.com/example/floating-notes/pull/482)"
        )
        h.caret(atEndOfLine: 2)
        h.type(String(repeating: "가나다라마바사 ", count: 6))
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

    /// 코드 블록의 복사 버튼, 체크박스, 꺾쇠, 링크 위에서는 화살표, 글자 위에서는 I자 커서(규칙 9). 텍스트 뷰가
    /// 마우스가 움직일 때마다 I자 커서를 넣어도, 누를 수 있는 것 위에서는 화살표로 남는다.
    @Test func clickableOverlaysShowTheArrowCursor() throws {
        let host = try Host("[ ] 할 일\n> 토글\n\t안\n[링크](https://example.com)\n```\nlet x = 1\n```\n끝")
        let view = host.editor.controller.textView
        let controller = host.editor.controller
        func move(to point: CGPoint) throws {
            NSCursor.iBeam.set()
            view.mouseMoved(with: try host.mouseMoved(atWindowPoint: view.convert(point, to: nil)))
        }
        // 코드 블록에 올리면 복사 버튼이 나타난다. 버튼 위는 화살표다.
        try move(to: try #require(controller.textPoint(forLine: 5)))
        #expect(controller.hoveredCodeBlock != nil)
        #expect(NSCursor.current == NSCursor.iBeam)
        let button = controller.copyButton.frame
        try move(to: CGPoint(x: button.midX, y: button.midY))
        #expect(NSCursor.current == NSCursor.arrow)
        #expect(controller.isInteractive(at: CGPoint(x: button.midX, y: button.midY)))
        #expect(controller.hoveredCodeBlock != nil)
        // 체크박스, 꺾쇠, 링크.
        for point in [controller.gutterPoint(forLine: 0), controller.gutterPoint(forLine: 1), controller.textPoint(forLine: 3)] {
            try move(to: try #require(point))
            #expect(NSCursor.current == NSCursor.arrow)
        }
        // 보통 글자 위는 I자 커서이고, 블록을 떠나 버튼이 사라진 자리도 그렇다.
        try move(to: try #require(controller.textPoint(forLine: 7)))
        #expect(NSCursor.current == NSCursor.iBeam)
        #expect(!controller.isInteractive(at: CGPoint(x: button.midX, y: button.midY)))
    }
}

