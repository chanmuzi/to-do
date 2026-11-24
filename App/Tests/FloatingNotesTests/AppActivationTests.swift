import Library
import Agent
import Store
import AppKit
import Models
@_spi(Verification) @testable import NotePanel
import Routing
import Testing
@testable import FloatingNotes

/// 노트를 누르면 앱이 앞으로 온다는 결정(D-025)의 App 쪽: 사용자가 노트를 열거나 만들라고 하면 앱이 앞으로 오고,
/// 켤 때 되살린 창이나 숨김을 푼 창은 앱을 앞으로 가져오지 않는다. 메뉴 막대에는 앱의 메뉴가 시안 차례로 있다.
@MainActor
@Suite(.serialized) struct AppActivationTests {
    private let fixture: WiringFixture
    private var activations: Int { box.count }
    private let box = Counter()

    private final class Counter {
        var count = 0
    }

    init() throws {
        fixture = try WiringFixture()
        let box = box
        fixture.router.activateApp = { box.count += 1 }
    }

    @Test func openingOrCreatingANoteByRequestActivatesTheApp() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "열 노트"))
        #expect(fixture.router.route(.openNote(note.id)) == .handled)
        #expect(activations == 1)
        #expect(fixture.router.route(.newNote(NewNoteRequest())) == .handled)
        #expect(activations == 2)
    }

    @Test func hidingClosingAndFailedOpensDoNotActivate() throws {
        defer { fixture.cleanUp() }
        let id = try fixture.open("노트")
        fixture.router.route(.toggleAllNotesHidden)
        fixture.router.route(.toggleAllNotesHidden)
        fixture.router.route(.closeNoteWindow(id))
        #expect(fixture.router.route(.openNote(NoteID(rawValue: "없는 노트"))) == .failed)
        #expect(activations == 0)
    }

    /// 켤 때 되살린 창은 키 창으로 시키지도, 앱을 앞으로 가져오지도 않는다.
    @Test func restoringWindowsNeitherAsksForKeyNorActivates() throws {
        defer { fixture.cleanUp() }
        let id = try fixture.open("되살릴 노트")
        fixture.notePanels.closeWindow(id)
        try fixture.notePanels.open(id, focus: false)
        #expect(fixture.keyRequests(id) == 0)
        #expect(activations == 0)
    }

    /// 앱이 뒤에 있을 때(다른 앱에서 전역 단축키로 연 캡처 바) 닫히면 어느 노트에도 키 창을 돌려주지 않는다.
    /// 앞에 있던 앱이 그대로 입력을 받는다.
    @Test func captureOpenedFromAnotherAppReturnsNoKeyToANote() throws {
        defer { fixture.cleanUp() }
        let id = try fixture.open("쓰던 노트")
        fixture.pretendKey(id)
        fixture.isAppActive = false
        fixture.quickPanels.toggleCapture()
        fixture.quickPanels.toggleCapture()
        #expect(fixture.keyRequests(id) == 0)
        // 앱이 앞에 있었으면 돌려준다.
        fixture.isAppActive = true
        fixture.quickPanels.toggleCapture()
        fixture.quickPanels.toggleCapture()
        #expect(fixture.keyRequests(id) == 1)
    }

    @Test func mainMenuFollowsTheDesktopScreenOrder() {
        let appName = AppDelegate.displayName
        #expect(appName == "Float")
        let menu = MainMenu.make(appName: appName, table: .standard, dispatcher: fixture.commands)
        #expect(menu.items.map(\.title) == ["Float", "파일", "편집", "서식", "보기", "창", "도움말"])
        func visible(_ title: String) -> [String] {
            menu.items.first { $0.title == title }?.submenu?.items
                .filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) ?? []
        }
        #expect(visible("Float") == ["Float에 관하여", "설정...", "Float 종료"])
        #expect(visible("편집").contains("굵게"))
        #expect(visible("서식") == ["링크 추가"])
        #expect(visible("보기") == ["노트 모두 숨기기", "본문 확대", "본문 축소", "본문 기본 크기"])
        #expect(visible("창") == ["다음 노트로"])
        #expect(visible("도움말") == ["단축키"])
        // 규칙 4: 보이는 항목에는 단축키가 적혀 있지 않다.
        let all = menu.items.compactMap(\.submenu).flatMap(\.items).filter { !$0.isHidden }
        #expect(all.allSatisfy { $0.keyEquivalent.isEmpty })
    }
}

extension AppActivationTests {
    @Test func barAndResultViewRecordFocusIntentWithoutLibraryActivation() throws {
        defer { fixture.cleanUp() }
        var events: [String] = []
        fixture.router.traceActivation = { events.append($0) }
        fixture.quickPanels.traceActivation = fixture.router.traceActivation
        let agent = AgentWindowCoordinator(store: AgentStore(location: fixture.location), theme: fixture.theme) { Issue.record("\($0)") }
        fixture.router.agent = agent
        agent.allowsKeyWindows = false
        agent.onClose = { events.append("agent-close") }
        let note = try fixture.open("대상")
        fixture.isAppActive = false
        fixture.router.route(.requestAgent)
        fixture.router.route(.requestAgent)
        #expect(activations == 0 && fixture.keyRequests(note) == 0)
        fixture.router.route(.openAgentWindow(note))
        agent.window(for: note)?.close()
        fixture.router.showAgent(try agent.record(for: note), source: "toast")
        agent.window(for: note)?.close()
        #expect(events == ["request-open bar", "request-close restore", "agent-open note", "agent-close", "agent-open toast", "agent-close"])
        #expect(activations == 2)
    }
}

extension AppActivationTests {
    @Test func globalNewNoteResultOpensPreviewThenReservedNote() async throws {
        defer { fixture.cleanUp() }
        let agent = AgentWindowCoordinator(store: .init(location: fixture.location), theme: fixture.theme) { Issue.record("\($0)") }
        let library = LibraryCoordinator(theme: fixture.theme, notes: fixture.notes, spaces: fixture.spaces, windows: fixture.windowStates,
                                         preferences: try .init(location: fixture.location), router: fixture.router)
        library.allowsKeyWindows = false
        defer { library.close() }
        fixture.router.library = library
        fixture.router.connectHistory(library.model, agent: agent)
        let controller = TodoProposalController(agent: agent, notes: fixture.notes, panels: fixture.notePanels, theme: fixture.theme, router: fixture.router)
        controller.connect(library.model)
        let draft = try agent.record(for: nil)
        var request = AgentRequest(id: UUID(), text: "새 노트", engine: "fixture", model: nil)
        let args = try JSONDecoder().decode(ProposalArguments.self, from: Data(#"{"kind":"create_note","title":"정리","markdown":"내용"}"#.utf8))
        let reserved = NoteID.make()
        let p = try AgentProposal.submitted(.init(arguments: args, version: nil), key: "new", request: request, source: nil, reservedID: reserved)
        request.proposals = [p]
        draft.change { $0.requests = [request] }
        controller.open(p.id, source: "conversation")
        #expect(activations == 1 && library.model.selectedProposal == p.id)
        #expect(try fixture.notes.list().notes.isEmpty)
        controller.accept([p.id], source: "library")
        #expect(activations == 2 && fixture.notePanels.window(for: reserved) != nil)
        try await agent.delete(draft)
        #expect(try fixture.notes.load(reserved).title == "정리")
    }
}

extension AppActivationTests {
    @Test func instructionResultOpensPreviewAndAcceptedDocument() throws {
        defer { fixture.cleanUp() }
        let store = AgentStore(location: fixture.location)
        let agent = AgentWindowCoordinator(store: store, theme: fixture.theme) { Issue.record("\($0)") }
        let library = LibraryCoordinator(theme: fixture.theme, notes: fixture.notes, spaces: fixture.spaces, windows: fixture.windowStates,
                                         preferences: try .init(location: fixture.location), router: fixture.router)
        library.allowsKeyWindows = false
        defer { library.close() }
        fixture.router.library = library
        fixture.router.connectHistory(library.model, agent: agent)
        let controller = TodoProposalController(agent: agent, notes: fixture.notes, panels: fixture.notePanels, theme: fixture.theme, router: fixture.router)
        controller.connect(library.model)
        let draft = try agent.record(for: nil)
        var request = AgentRequest(id: UUID(), text: "앞으로 짧게 답해 줘", engine: "fixture", model: nil)
        let fields = ["kind": "change_instructions", "before": "", "after": "짧게", "user_message": request.userText]
        let args = try JSONDecoder().decode(ProposalArguments.self, from: JSONEncoder().encode(fields))
        let p = try AgentProposal.submitted(.init(arguments: args, version: TodoSubmission.fingerprint(Data())), key: "rule",
                                            request: request, source: nil, reservedID: .make())
        request.proposals = [p]
        draft.change { $0.requests = [request] }
        controller.open(p.id, source: "conversation")
        #expect(activations == 1 && library.model.selectedProposal == p.id)
        controller.accept([p.id], source: "library")
        controller.open(p.id, source: "conversation")
        #expect(activations == 2 && library.model.selection == .memory && fixture.notePanels.openNoteIDs.isEmpty)
        #expect(try store.readInstructions() == "짧게")
    }
}
