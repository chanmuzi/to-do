@testable import Agent
import AppKit
@_spi(Verification) import Capture
import FloatSettings
import Library
import Models
import Scheduling
import Store
import Testing
import Theme
@testable import FloatingNotes

@Suite(.serialized) @MainActor struct AgentButtonClickTests {
    private func buttons(in window: NSWindow) -> [String: AnyObject] {
        var result: [String: AnyObject] = [:]
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: AnyObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let element = object as? NSObject, element.responds(to: NSSelectorFromString("accessibilityRole")) {
                if let role = object.accessibilityRole?(), [NSAccessibility.Role.button, .checkBox, .init(rawValue: "AXSwitch")].contains(role), let name = object.accessibilityLabel?() {
                    result[name] = element
                }
                for child in object.accessibilityChildren?() ?? [] { visit(child as AnyObject) }
            }
            if let view = object as? NSView { view.subviews.forEach(visit) }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        if let root = window.contentView { visit(root) }
        return result
    }

    @Test func proposalCardActionsUseTheDisplayedID() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let release = TestAccessibility.enableForTest()
        defer { release() }
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        let id = try fx.open("테스트")
        let draft = try agent.record(for: id)
        let bytes = try Data(fx.notes.proposalText(id).utf8)
        let input = TodoSubmission(noteID: id.rawValue, lines: ["확인"], version: TodoSubmission.fingerprint(bytes))
        var request = AgentRequest(id: UUID(), text: "정리", engine: "fixture", model: nil)
        let first = AgentProposal.submitted(input, key: "a", request: request, source: nil)
        let second = AgentProposal.submitted(input, key: "b", request: request, source: nil)
        request.proposals = [first, second]
        draft.change { $0.requests.append(request) }
        let controller = TodoProposalController(agent: agent, notes: fx.notes, panels: fx.notePanels, theme: fx.theme, router: fx.router)
        var events: [String] = []
        fx.router.traceActivation = { events.append($0) }
        var undo: (() -> Void)?
        controller.showToast = { _, _, action in undo = action }
        controller.start()
        controller.open(first.id, source: "toast")
        func press(_ name: String) async throws {
            try await Task.sleep(for: .milliseconds(150))
            let card = try #require(controller.card(for: id))
            let button = try #require(buttons(in: card)[name])
            #expect(button.accessibilityPerformPress?() == true)
        }
        try await press("받기")
        #expect(draft.proposal(first.id)?.status == .accepted)
        undo?()
        #expect(try Data(fx.notes.proposalText(id).utf8) == bytes)
        controller.open(second.id, source: "library")
        try await press("버리기")
        #expect(draft.proposal(second.id)?.status == .discarded)
        #expect(events == ["proposal-open toast", "proposal-accept card", "proposal-open library", "proposal-discard card"])
    }

    @Test(arguments: [false, true]) func requestGroupAcceptsOnlyMatchingTargetsAndUndoesItsOwnWrites(mixed: Bool) async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let release = TestAccessibility.enableForTest()
        defer { release() }
        let agent = AgentWindowCoordinator(store: .init(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        let target = try fx.open("대상")
        let other = try fx.open("바뀐 대상")
        let before = try Data(fx.notes.proposalText(target).utf8)
        var request = AgentRequest(id: UUID(), text: "요청 묶음", engine: "fixture", model: nil)
        for (index, note) in [target, target, other].enumerated() {
            let bytes = try Data(fx.notes.proposalText(note).utf8)
            let input = TodoSubmission(noteID: note.rawValue, lines: ["항목 \(index)"], version: TodoSubmission.fingerprint(bytes))
            request.proposals.append(.submitted(input, key: String(index), request: request, source: nil))
        }
        if mixed {
            let version = TodoSubmission.fingerprint(before)
            let base = ["note_id": target.rawValue, "title": "일정 확인", "time_zone": "Asia/Seoul", "start": "2028-02-29"]
            for kind in ["add_reminder", "add_event", "create_note"] {
                var args: [String: Any] = base
                args["kind"] = kind
                args["date_only"] = true
                if kind == "add_event" { args["end"] = "2028-03-01" }
                if kind == "create_note" { args = ["kind": kind, "title": "묶음 노트", "markdown": "본문"] }
                let input = try JSONDecoder().decode(ProposalArguments.self, from: JSONSerialization.data(withJSONObject: args))
                request.proposals.append(try .submitted(.init(arguments: input, version: version), key: kind, request: request,
                                                        source: target, reservedID: .make()))
            }
        }
        let draft = try agent.record(for: target)
        draft.change { $0.requests = [request] }
        try fx.notes.update(other) { $0.body = "나중에 바꾼 글" }
        let library = LibraryCoordinator(theme: fx.theme, notes: fx.notes, spaces: fx.spaces, windows: fx.windowStates,
                                         preferences: try LibraryPreferencesStore(location: fx.location), router: fx.router)
        library.allowsKeyWindows = false
        let model = library.model
        fx.router.connectHistory(model, agent: agent)
        let controller = TodoProposalController(agent: agent, notes: fx.notes, panels: fx.notePanels, theme: fx.theme, router: fx.router)
        controller.connect(model)
        var undo: (() -> Void)?
        controller.showToast = { _, _, action in undo = action }
        library.show()
        defer { library.close() }
        model.select(.proposals)
        model.previewProposalHover = request.id
        try await Task.sleep(for: .milliseconds(160))
        let window = try #require(library.window)
        let button = try #require(buttons(in: window)["모두 받기"])
        #expect(button.accessibilityPerformPress?() == true)
        let values = draft.conversation.requests[0].proposals
        let initial: [AgentProposal.Status] = [.accepted, .accepted, .pending]
        #expect(values.map(\.status) == initial + (mixed ? [.accepted, .accepted, .accepted] : []))
        #expect(values[2].requiresReview == true)
        undo?()
        if mixed {
            #expect(try fx.notes.load(target).body.isEmpty)
            #expect(try fx.notes.load(target).schedules.isEmpty)
            #expect(try fx.notes.listTrash().notes.first?.id == values.last?.createdNoteID)
        } else {
            #expect(try Data(fx.notes.proposalText(target).utf8) == before)
        }
        #expect(try fx.notes.load(other).body == "나중에 바꾼 글")
        model.selectProposal(values[0].id, collapsible: true)
        #expect(model.selectedProposal == values[0].id)
        model.selectProposal(values[0].id, collapsible: true)
        #expect(model.selectedProposal == nil)
        try await agent.delete(draft)
        #expect(model.proposalRequests.isEmpty)
    }

    @Test func barAndConversationButtonsDeliverTheirActions() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        fx.router.route(.requestAgent)
        let bar = try #require(fx.capture.window)
        try await Task.sleep(for: .milliseconds(200))
        let toggle = try #require(buttons(in: bar)["메모로 전환"])
        #expect(toggle.accessibilityPerformPress?() == true)
        #expect(fx.capture.mode == .memo)
        fx.capture.hide()
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let note = try fx.open("대상")
        fx.router.agent = agent
        fx.router.route(.openAgentWindow(note))
        let window = try #require(agent.window(for: note))
        defer { window.close() }
        let draft = try agent.record(for: note)
        var sends = 0
        agent.send = { _ in sends += 1 }
        let one = AgentConversation.Queued(text: "하나")
        draft.change { $0.draft = "글"; $0.queued = [one] }
        agent.performForVerification("hover", for: note)
        try await Task.sleep(for: .milliseconds(80))
        let items = buttons(in: window)
        for name in ["보내기", "고치기", "빼기", "지금 보내기"] { #expect(items[name] != nil) }
        let rects = try ["고치기", "빼기", "지금 보내기"].map { label in
            try #require(items[label]?.accessibilityFrame?())
        }
        #expect(rects.allSatisfy { $0.width == 20 && $0.height == 20 })
        #expect(rects[1].minX - rects[0].maxX == 2)
        #expect(rects[2].minX - rects[1].maxX == 2)
        #expect(items["보내기"]?.accessibilityPerformPress?() == true && sends == 1)
        #expect(items["고치기"]?.isAccessibilityEnabled?() == false)
        var selected: UUID?
        agent.sendNow = { _, id in selected = id }
        #expect(items["지금 보내기"]?.accessibilityPerformPress?() == true && selected == one.id)
        #expect(items["빼기"]?.accessibilityPerformPress?() == true && draft.conversation.queued.isEmpty)
    }
}

extension AgentButtonClickTests {
    @Test func historyLibraryCornerAndSettingsActions() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let note = try fx.open("대상")
        fx.router.agent = agent
        agent.present = fx.router.showAgent
        var trace: [String] = []
        fx.router.traceActivation = { trace.append($0) }
        var sends = 0
        agent.send = { _ in sends += 1 }
        let draft = try agent.record(for: note)
        var request = AgentRequest(id: UUID(), text: "회의", engine: "fixture", model: nil)
        request.status = .awaitingAnswer
        draft.change { $0.requests.append(request) }

        let library = LibraryCoordinator(theme: fx.theme, notes: fx.notes, spaces: fx.spaces, windows: fx.windowStates,
                                        preferences: try LibraryPreferencesStore(location: fx.location), router: fx.router)
        fx.router.connectHistory(library.model, agent: agent)
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        library.model.select(.conversations)
        library.model.previewSectionHover = true
        let lib = try #require(library.window)
        func press(_ name: String, in window: NSWindow) async throws {
            try await Task.sleep(for: .milliseconds(120))
            let button = try #require(buttons(in: window)[name], "버튼 \(name)")
            #expect(button.accessibilityPerformPress?() == true)
        }
        #expect(draft.conversation.seenAt == nil && trace.isEmpty)
        try await press("에이전트에게 요청", in: lib)
        #expect(fx.capture.mode == .request)
        fx.capture.hide()
        func findRow(_ view: NSView) -> HistoryRowInputView? {
            if let row = view as? HistoryRowInputView, row.id == draft.conversation.id { return row }
            return view.subviews.lazy.compactMap(findRow).first
        }
        let root = try #require(lib.contentView)
        root.layoutSubtreeIfNeeded()
        let row = try #require(findRow(root))
        let point = row.convert(.init(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        func click(_ count: Int) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: lib.windowNumber, context: nil,
                    eventNumber: 0, clickCount: count, pressure: 1))
                lib.sendEvent(event)
            }
        }
        try click(1)
        #expect(row.window === lib)
        #expect(library.model.selectedConversation == draft.conversation.id && draft.conversation.seenAt == nil)
        try click(2)
        try await Task.sleep(for: .milliseconds(120))
        #expect(draft.conversation.needsAnswer && draft.conversation.seenAt != nil)
        let panel = try #require(agent.window(for: note))
        try await press("지난 대화", in: panel)
        #expect(draft.showsHistory)
        try await press("회의", in: panel)
        #expect(!draft.showsHistory && agent.window(for: note) === panel)
        try await press("새 대화", in: panel)
        let fresh = try #require(agent.window(for: note))
        defer { fresh.close() }
        let freshDraft = try agent.record(for: note)
        #expect(panel !== fresh && freshDraft.conversation.requests.isEmpty)
        try await press("새 대화", in: lib)
        let global = try agent.record(for: nil)
        defer { agent.window(id: global.conversation.id)?.close() }
        let corner = AgentCorner(theme: fx.theme, agent: agent, router: fx.router, notes: fx.notePanels)
        corner.setEnabled(true)
        defer { corner.setEnabled(false) }
        let circle = try #require(corner.window)
        #expect(!circle.canBecomeKey && !circle.canBecomeMain)
        try await press("에이전트 열기", in: circle)
        defer { agent.window(id: draft.conversation.id)?.close() }
        #expect(trace == ["agent-open library", "agent-open clock", "agent-open new", "agent-open library-new", "agent-open corner"])
        #expect(sends == 0 && !lib.isKeyWindow)
        for screen in [CGRect(x: 0, y: 70, width: 1000, height: 650), CGRect(x: -1200, y: 10, width: 1200, height: 850)] {
            let frame = AgentCorner.circleFrame(visible: screen, diameter: 40, inset: 10)
            #expect(frame.maxX == screen.maxX - 10 && frame.minY == screen.minY + 10)
        }

        let store = try AppSettingsStore(stateDirectory: fx.location.stateDirectory)
        let old = try JSONDecoder().decode(SettingsValues.self, from: Data("{}".utf8))
        #expect(old.showsNoteAgent && !old.showsCornerAgent)
        let service = ScheduleService(notes: fx.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fx.location), read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fx.theme)
        settings.allowsKeyWindows = false
        settings.show(.assistant)
        defer { settings.window?.close() }
        let preferences = try #require(settings.window)
        for (label, noteOn, cornerOn) in [("화면 구석 단추", true, true), ("노트에 표시", false, true),
                                            ("화면 구석 단추", false, false), ("노트에 표시", true, false)] {
            try await press(label, in: preferences)
            let saved = try AppSettingsStore(stateDirectory: fx.location.stateDirectory).settings
            #expect(saved.showsNoteAgent == noteOn && saved.showsCornerAgent == cornerOn)
        }
        settings.show(.general)
        try await press("리마인더 있는 노트", in: preferences)
        try await press("마지막으로 본 곳에서 열기", in: preferences)
        let sidebar = try LibraryPreferencesStore(location: fx.location).value
        #expect(sidebar.visibleViews.contains(.reminders))
        #expect(!sidebar.opensLastSelection)
    }
}

extension AgentButtonClickTests {
    @Test func confirmationCommandsAndHeldQueueWidths() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let release = TestAccessibility.enableForTest()
        defer { release() }
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        let note = try fx.open("검사")
        let draft = try agent.record(for: note)
        let frame = CGRect(x: 40, y: 100, width: 340, height: 240)
        agent.open(record: draft, title: "", frame: frame, visible: .init(x: 0, y: 0, width: 900, height: 800))
        let window = try #require(agent.window(for: note))
        defer { window.close() }

        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func settle() async throws { try await Task.sleep(for: .milliseconds(120)); window.contentView?.layoutSubtreeIfNeeded() }
        try await settle()
        let root = try #require(window.contentView)
        let anchor = try #require(root.conversationButton(draft.conversation.id))
        anchor.showMenu()
        let emptyMenu = try #require(window.childWindows?.last)
        let emptyItems = descendants(try #require(emptyMenu.contentView)).compactMap { $0 as? PickerMenuRow }
        #expect(emptyItems.map { $0.accessibilityLabel() } == ["이름 바꾸기", "지우기"])
        #expect(emptyItems.allSatisfy { !$0.isAccessibilityEnabled() })
        emptyMenu.close()

        var request = AgentRequest(id: UUID(), text: "원래 이름", engine: "fixture", model: nil)
        request.status = .failed
        draft.change {
            $0.requests.append(request)
            $0.queued = [.init(text: "첫째"), .init(text: "둘째")]
        }
        draft.queueHeld = true
        try await settle()
        anchor.showMenu()
        let menu = try #require(window.childWindows?.last)
        #expect(menu.frame.width == 170)
        #expect(!menu.canBecomeKey)
        let items = descendants(try #require(menu.contentView)).compactMap { $0 as? PickerMenuRow }
        #expect(items.first?.accessibilityPerformPress() == true)
        try await settle()
        let field = try #require(descendants(root).compactMap { $0 as? CommandInputField }.first { $0.accessibilityLabel() == "대화 이름" })
        field.stringValue = "고친 이름"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        let editor = NSTextView()
        #expect(field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == true)
        #expect(draft.conversation.name == "고친 이름")
        #expect(draft.rename("   ") && draft.conversation.name == "고친 이름")
        try await settle()
        anchor.confirmDeletion()
        let confirmation = try #require(window.childWindows?.last as? ConfirmationPopover)
        #expect(confirmation.frame.width == 236 && !confirmation.canBecomeKey)
        #expect(confirmation.handleKey(36) && confirmation.isVisible)
        #expect(confirmation.handleKey(53) && !confirmation.isVisible && !draft.deleted)
        anchor.confirmDeletion()
        let second = try #require(window.childWindows?.last as? ConfirmationPopover)
        second.pressed(in: window)
        #expect(!second.isVisible && !draft.deleted)
        var sent = false
        agent.sendAll = { _ in sent = true }
        for width in [340, 300, 260] {
            window.setContentSize(.init(width: CGFloat(width), height: window.frame.height))
            try await settle()
            let controls = buttons(in: window)
            let remove = try #require(controls["모두 빼기"])
            let send = try #require(controls["모두 보내기"])
            let left = try #require(remove.accessibilityFrame?()), right = try #require(send.accessibilityFrame?())
            #expect(left.height == 22 && right.height == 22 && abs(right.minX - left.maxX - 6) <= 1)
            if width == 300 { #expect(send.accessibilityPerformPress?() == true && sent) }
            if width == 260 { #expect(remove.accessibilityPerformPress?() == true && draft.conversation.queued.isEmpty) }
        }
        anchor.confirmDeletion()
        let final = try #require(window.childWindows?.last)
        try await settle()
        #expect(buttons(in: final)["삭제"]?.accessibilityPerformPress?() == true)
        try await settle()
        #expect(draft.deleted && agent.window(for: note) == nil)
    }
}

extension AgentButtonClickTests {
    @Test func libraryMenuEditsOnlyItsRowAndOpensTheSameConversation() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let release = TestAccessibility.enableForTest()
        defer { release() }
        let agent = AgentWindowCoordinator(store: AgentStore(location: fx.location), theme: fx.theme) { Issue.record("\($0)") }
        agent.allowsKeyWindows = false
        fx.router.agent = agent
        let draft = agent.newRecord()
        draft.change {
            var request = AgentRequest(id: UUID(), text: "첫 이름", engine: "fixture", model: nil)
            request.status = .completed
            $0.requests.append(request)
        }
        let library = LibraryCoordinator(theme: fx.theme, notes: fx.notes, spaces: fx.spaces, windows: fx.windowStates,
                                        preferences: try LibraryPreferencesStore(location: fx.location), router: fx.router)
        fx.router.connectHistory(library.model, agent: agent)
        var opens: [UUID] = []
        library.model.openConversation = { opens.append($0) }
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        library.model.select(.conversations)
        library.model.previewHistoryHover = draft.conversation.id
        try await Task.sleep(for: .milliseconds(180))
        let win = try #require(library.window), root = try #require(win.contentView)
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        root.layoutSubtreeIfNeeded()
        let anchor = try #require(root.conversationButton(draft.conversation.id))
        #expect(anchor.bounds.size == CGSize(width: 24, height: 24))
        func items() throws -> [PickerMenuRow] {
            let popup = try #require(win.childWindows?.last?.contentView)
            return views(popup).compactMap { $0 as? PickerMenuRow }
        }
        let row = try #require(views(root).compactMap { $0 as? HistoryRowInputView }.first)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        row.rightMouseDown(with: event)
        let contextItems = try items()
        #expect(contextItems.map { $0.accessibilityLabel() } == ["열기", "이름 바꾸기", "지우기"])
        #expect(contextItems[0].accessibilityPerformPress())
        #expect(opens == [draft.conversation.id])
        anchor.showMenu()
        #expect(try items()[1].accessibilityPerformPress())
        try await Task.sleep(for: .milliseconds(120))
        let field = try #require(views(root).compactMap { $0 as? CommandInputField }.first { $0.accessibilityLabel() == "대화 이름" })
        field.stringValue = "취소할 이름"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(field.delegate?.control?(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true)
        #expect(draft.conversation.name == "첫 이름" && !win.isKeyWindow)
    }
}

extension AgentButtonClickTests {
    @Test func memoryButtonOpensStandaloneEditorAndCloseFlushes() async throws {
        let fx = try WiringFixture()
        defer { fx.cleanUp() }
        let release = TestAccessibility.enableForTest()
        defer { release() }
        let store = AgentStore(location: fx.location)
        let host = InstructionEditor(theme: fx.theme, store: store)
        let library = LibraryCoordinator(theme: fx.theme, notes: fx.notes, spaces: fx.spaces, windows: fx.windowStates,
                                         preferences: try .init(location: fx.location), router: fx.router)
        library.model.instructionView = host.editor.view
        library.model.openInstructions = host.open
        library.model.flushInstructions = store.flushInstructions
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        let window = try #require(library.window)
        for _ in 0..<40 where buttons(in: window)["메모리"] == nil { try await Task.sleep(for: .milliseconds(25)) }
        let button = try #require(buttons(in: window)["메모리"])
        #expect(button.accessibilityPerformPress?() == true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(library.model.selection == .memory && !library.model.showsNewNote)
        let editor = host.editor
        #expect(editor.view.window === window && !editor.configuration.recognizesDates && editor.onAcceptDate == nil)
        let body = try #require(editor.documentView as? NSTextView)
        body.setMarkedText("하", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
        body.insertText("한글", replacementRange: body.markedRange())
        library.close()
        #expect(try store.readInstructions() == "한글")
        library.show()
        #expect(editor.text == "한글" && library.model.rows.isEmpty)
    }
}
