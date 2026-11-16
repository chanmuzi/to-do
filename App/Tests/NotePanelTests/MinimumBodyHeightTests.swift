import AppKit
import Models
import Store
import Testing
@testable import NotePanel

/// 노트 창의 가장 낮은 높이(D-031): 글이 한두 줄이어도 본문 영역은 네 줄만큼이고, 그보다 긴 글은
/// 한도까지 창이 따라 늘어 스크롤 없이 다 보인다.
@Suite @MainActor struct MinimumBodyHeightTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private var chrome: CGFloat {
        fixture.theme.shape(.chromeHeight) + fixture.theme.shape(.borderWidth)
    }

    private func bodyHeight(lines: Int) -> CGFloat {
        let padding = fixture.theme.docPadding
        return fixture.theme.lineHeight(.body) * CGFloat(lines) + padding.top + padding.bottom
    }

    private func open(
        _ body: String, in coordinator: NotePanelCoordinator
    ) throws -> (NoteWindowController, NSScrollView) {
        let note = try fixture.notes.create(NoteDraft(body: body))
        try coordinator.open(note.id, focus: false)
        let controller = try #require(coordinator.controllers[note.id])
        controller.root.layoutSubtreeIfNeeded()
        return (controller, try #require(controller.editor.view.enclosingScrollView))
    }

    @Test func policyKeepsFourBodyLinesFromTheToken() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let (controller, _) = try open("", in: coordinator)
        let policy = controller.environment.sizePolicy

        #expect(fixture.theme.count(.noteBodyLinesMin) == 4)
        #expect(policy.minBodyHeight == bodyHeight(lines: 4))
        #expect(policy.minHeight == chrome + bodyHeight(lines: 4))
        #expect(controller.panel.contentMinSize.height == policy.minHeight)
    }

    /// 새 노트(빈 노트), 한 줄, 두 줄, 네 줄 노트는 모두 같은 높이로 뜬다.
    @Test(arguments: ["", "한 줄", "한 줄\n두 줄", "하나\n둘\n셋\n넷"])
    func shortNotesOpenAtTheMinimumHeight(body: String) throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let (controller, scrollView) = try open(body, in: coordinator)

        #expect(controller.panel.frame.height == chrome + bodyHeight(lines: 4))
        #expect(scrollView.frame.height == bodyHeight(lines: 4))
        // 스크롤할 것이 없다.
        #expect(controller.editor.view.frame.height <= scrollView.contentSize.height)
        #expect(scrollView.contentView.bounds.origin == .zero)
    }

    /// 사용자가 본 문제: 여러 줄인 노트가 두 줄쯤의 높이에 머물고 그 안에서 스크롤됐다. 창을 처음 띄우는
    /// 배치 도중에 알게 된 내용 높이가 창과 본문 영역에 끝까지 반영되는지 본다.
    @Test func aTwelveLineNoteOpensAtItsFullHeightWithNothingToScroll() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let body = (1...12).map { "\($0)번째 줄" }.joined(separator: "\n")
        let (controller, scrollView) = try open(body, in: coordinator)

        #expect(controller.contentHeight == bodyHeight(lines: 12))
        #expect(controller.panel.frame.height == chrome + bodyHeight(lines: 12))
        // 본문 영역이 창을 따라 커졌고, 문서 높이가 보이는 높이와 같다.
        #expect(scrollView.frame.height == bodyHeight(lines: 12))
        #expect(scrollView.frame.maxY == controller.root.bounds.maxY)
        #expect(controller.editor.view.frame.height == scrollView.documentVisibleRect.height)
        #expect(scrollView.documentVisibleRect.origin == .zero)
        // 스크롤 막대가 보이지 않는다.
        #expect(scrollView.verticalScroller?.isHidden != false)
    }

    /// 다시 켜며 되살린 노트: 적어 둔 틀이 낮아도 가장 낮은 높이로, 글이 길면 글 높이로 뜬다.
    @Test func restoredNotesGetTheMinimumOrTheirContentHeight() throws {
        defer { fixture.cleanUp() }
        let short = try fixture.notes.create(NoteDraft(title: "짧은 노트", body: "한 줄"))
        let long = try fixture.notes.create(
            NoteDraft(title: "긴 노트", body: (1...12).map { "\($0)" }.joined(separator: "\n"))
        )
        let states = try WindowStateStore(location: fixture.location)
        // 예전 판이 적어 둔 한 줄짜리 틀.
        let old = CGRect(x: 120, y: 400, width: 340, height: chrome + bodyHeight(lines: 1))
        try states.set(NoteWindowState(frame: WindowFrame(old), isOpen: true, stackOrder: 1), for: short.id)
        try states.set(NoteWindowState(frame: WindowFrame(old), isOpen: true, stackOrder: 2), for: long.id)

        let coordinator = try fixture.makeCoordinator()
        defer { coordinator.controllers.values.forEach { $0.discardWindow() } }
        coordinator.restoreOpenNotes()
        let shortPanel = try #require(coordinator.controllers[short.id]).panel
        let longController = try #require(coordinator.controllers[long.id])
        longController.root.layoutSubtreeIfNeeded()

        #expect(shortPanel.frame.height == chrome + bodyHeight(lines: 4))
        #expect(shortPanel.frame.maxY == old.maxY)
        #expect(longController.panel.frame.height == chrome + bodyHeight(lines: 12))
        #expect(longController.panel.frame.maxY == old.maxY)
        let scrollView = try #require(longController.editor.view.enclosingScrollView)
        #expect(longController.editor.view.frame.height == scrollView.documentVisibleRect.height)
    }

    /// 글을 지워 줄어드는 노트는 가장 낮은 높이에서 멈춘다.
    @Test func shrinkingStopsAtTheMinimumHeight() async throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let (controller, _) = try open("하나\n둘\n셋\n넷\n다섯\n여섯", in: coordinator)
        let top = controller.panel.frame.maxY
        #expect(controller.panel.frame.height == chrome + bodyHeight(lines: 6))
        let textView = try #require(controller.editor.view as? NSTextView)

        textView.insertText("한 줄만", replacementRange: NSRange(location: 0, length: (textView.string as NSString).length))

        #expect(await fixture.wait { controller.heightTarget == nil })
        #expect(controller.panel.frame.height == chrome + bodyHeight(lines: 4))
        #expect(controller.panel.frame.maxY == top)
    }

    /// 글이 가장 낮은 높이보다 짧아도 본문 뷰가 본문 영역을 채운다. 글 아래의 빈 자리를 눌러도 본문이 받는다.
    @Test func aShortBodyStillFillsTheBodyAreaSoPressesBelowTheTextReachIt() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        let (controller, scrollView) = try open("한 줄", in: coordinator)
        let body = controller.editor.view

        #expect(body.frame.height == scrollView.contentSize.height)
        // 본문 영역의 맨 아래 줄 자리(상단 줄과 오른쪽 아래 버튼을 비켜난 곳).
        let root = controller.root
        let point = NSPoint(x: fixture.theme.docPadding.leading + 4, y: root.bounds.maxY - 6)
        let hit = root.hitTest(root.superview?.convert(point, from: root) ?? point)
        #expect(hit === body)
    }
}
