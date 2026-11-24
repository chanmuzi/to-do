@testable import Agent
import AppKit
@_spi(Verification) import Editor
@testable import FloatSettings
import Library
@_spi(Verification) import NotePanel
import Models
import Scheduling
import Store
import SwiftUI
import Testing
import Theme
@testable import FloatingNotes

@Suite struct SettingsWindowTests {
    @Test func inlinePickerLimitsOnlyTheModelNameAndSharesSettings() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let theme = fixture.theme
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings },
                                  save: store.update, schedules: ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(),
                                  makeBridge: { FakeCalendarBridge() }), shortcuts: [], openPrivacy: { _ in })
        let menu = model.choices.menu(.both, theme: theme)
        model.chooseModelOption(try #require(menu.item(withTitle: "Opus")))
        model.chooseModelOption(try #require(menu.item(withTitle: "High")))
        #expect(store.settings.agentModel == "opus" && model.selectedEffort == "high")
        #expect(model.choices.menu(.both, theme: theme).items.filter { $0.state == .on }.map(\.title) == ["Opus", "High"])
        let name = String(repeating: "Research Preview ", count: 6)
        let control = InlineValuePopup(theme: theme, name: name, detail: "High", visible: true,
                                       label: name, makeMenu: { menu }, choose: model.chooseModelOption)
        let host = NSHostingView(rootView: control.fixedSize())
        let size = host.fittingSize
        let font = theme.nsFont(.body, size: theme.component(.agentModelFont))
        let detail = ceil(("High" as NSString).size(withAttributes: [.font: font]).width)
        #expect(size.width == theme.component(.agentModelNameMax) + detail + theme.component(.captureValueGap) * 4 + theme.component(.agentModelChevron))
        #expect(!font.isFixedPitch)
    }

    @Test func hoveringModelPreservesInputHeightAndLines() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let theme = fixture.theme
        let draft = AgentDraft(.init(targets: []), store: AgentStore(location: fixture.location))
        let modelName = "Opus 5.5 Research Preview Extended"
        let view = AgentWindowView(theme: theme, modelPicker: { visible, space in
            AnyView(InlineValuePopup(theme: theme, name: modelName, detail: "High", visible: visible, lineSpace: space,
                                     label: modelName, makeMenu: { NSMenu() }, choose: { _ in }))
        }, title: "", draft: draft, history: { [] }, openHistory: { _ in }, newChat: {}, delete: {}, send: {},
           sendAll: {}, retry: { _ in }, sendNow: { _ in }, openNote: { _ in }, chooseTarget: {},
           titleForNote: { _ in nil }, fit: { _ in }, close: {})
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 235), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        window.contentView = host
        func find<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
            if let match = root as? T { return match }
            return root.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        func settle() async throws {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            host.layoutSubtreeIfNeeded()
        }
        try await settle()
        let field = try #require(find(CommandInputField.self, in: host))
        func snapshot() throws -> (CGRect, Int) {
            let value = field.stringValue.isEmpty ? field.placeholderAttributedString : field.attributedStringValue
            let storage = NSTextStorage(attributedString: try #require(value))
            let layout = NSLayoutManager()
            let cell = try #require(field.cell)
            let container = NSTextContainer(size: CGSize(width: cell.titleRect(forBounds: field.bounds).width,
                                                         height: .greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            var lines = 0
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
            return (field.convert(field.bounds, to: host), lines)
        }
        for (text, shouldShow, expectedLines) in [("", true, 1), ("짧은 글", true, 1),
                                                 (String(repeating: "가", count: 25), true, 2),
                                                 ("윗줄\n짧게", true, 2), ("윗줄\n마지막 줄에는 글을 길게 적어 둡니다", false, 2)] {
            draft.update(text)
            draft.previewInputHover = false
            try await settle()
            let before = try snapshot()
            #expect(before.1 == expectedLines)
            draft.previewInputHover = true
            try await settle()
            let after = try snapshot()
            #expect(before == after)
            func picker(in view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.title == modelName { return button }
                return view.subviews.lazy.compactMap(picker).first
            }
            let button = try #require(picker(in: host))
            #expect((button.frame.width > theme.shape(.borderWidth) && button.layer?.opacity == 1) == shouldShow)
            if text.isEmpty {
                let placeholder = try #require(field.placeholderAttributedString)
                let start = try #require(field.cell).titleRect(forBounds: field.bounds).minX
                #expect(button.convert(button.bounds, to: field).minX > start + placeholder.size().width)
            }
            draft.previewInputHover = false
            try await settle()
            #expect(try snapshot() == before)
        }
    }

    @Test func routingReusesWindowAndRequestsOnlyOnConnect() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let fake = FakeCalendarBridge()
        fake.accessByKind = [.event: .needsRequest, .reminder: .blocked]
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { fake })
        service.preferredID = { store.settings[idFor: $0] }
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let coordinator = SettingsCoordinator(model: model, theme: fixture.theme)
        coordinator.allowsKeyWindows = false
        let router = AppRouter()
        router.notePanels = fixture.notePanels
        router.settingsWindow = coordinator
        #expect(router.route(.openSettings) == .handled)
        let window = try #require(coordinator.window)
        defer { window.close() }
        #expect(model.pane == .general)
        #expect(window.frame.size == NSSize(width: 700, height: 540))
        #expect(window.isMovableByWindowBackground && !window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
        window.cancelOperation(nil)
        #expect(!window.isVisible)
        #expect(router.route(.openShortcuts) == .handled)
        #expect(coordinator.window === window && model.pane == .shortcuts)
        coordinator.show(.schedule)
        #expect(fake.authorizationPromptAttempts.isEmpty)
        await model.connect(.event)
        await model.connect(.event)
        await model.connect(.reminder)
        #expect(fake.authorizationPromptAttempts == [.event])
        model.choose("work", for: .event)
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.calendarID == "work")
        let event = ScheduleItem(start: .now, end: .now.addingTimeInterval(3600))
        let target = try #require(service.destination(for: event))
        #expect(target.name == "업무" && target.color != nil)
        try service.start()
        defer { service.stop() }
        let note = try fixture.notes.create(NoteDraft(schedules: [event]))
        service.register(note.id, itemID: event.id, requestPermission: false)
        await service.flush()
        let linked = try #require(try fixture.notes.load(note.id).schedules.first)
        #expect(linked.link != nil && service.destination(for: linked) == target)
        fake.accessByKind = [.event: .blocked]
        model.refreshCalendars()
        #expect(store.settings.calendarID == "work")
        fake.accessByKind = [:]
        fake.additionalChoices[.event] = []
        model.refreshCalendars()
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.calendarID == nil)
        #expect(service.destination(for: event) == fake.eventDestination)
        #expect(service.destination(for: linked) == target)
        model.choose("shopping", for: .reminder)
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.reminderListID == "shopping")
        #expect(service.destination(for: ScheduleItem(start: .now))?.name == "장보기")
        fake.readOnlyIDs = ["shopping"]
        model.refreshCalendars()
        #expect(store.settings.reminderListID == nil)
        #expect(service.destination(for: ScheduleItem(start: .now)) == fake.reminderDestination)
    }

    @discardableResult
    private func checkMenu(_ settings: SettingsCoordinator, _ titles: [String], selected: String) throws -> NSMenu {
        func modelButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.accessibilityLabel() == "모델" { return button }
            return view.subviews.lazy.compactMap(modelButton).first
        }
        let root = try #require(settings.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let button = try #require(modelButton(in: root))
        let menu = try #require(button.menu)
        let items = menu.items
        #expect(items.enumerated().compactMap { $1.isSeparatorItem ? $0 : nil } == (titles.count > 1 ? [1] : []))
        #expect(items.filter { !$0.isSeparatorItem }.map(\.title) == titles)
        #expect(items.filter { $0.state == .on }.map(\.title) == [selected])
        #expect(button.title == selected)
        return menu
    }

    @Test func codexMenuKeepsFiveChoicesAndTheSavedSelection() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let catalog = fixture.root.appending(path: "models.json")
        let entries = (1...11).reversed().map { rank -> [String: Any] in
            ["slug": "m\(rank)", "display_name": "Model \(rank)", "visibility": "list", "priority": rank]
        }
        try JSONSerialization.data(withJSONObject: ["models": entries]).write(to: catalog)
        let cli = fixture.root.appending(path: "codex")
        try #"""
        #!/bin/sh
        case "$*" in
          --version) echo fake ;;
          "debug models") cat "$(dirname "$0")/models.json" ;;
          "login status") echo "Logged in using ChatGPT" ;;
          *) exit 1 ;;
        esac
        """#.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        try FileManager.default.createSymbolicLink(at: fixture.root.appending(path: "node"),
                                                   withDestinationURL: URL(filePath: "/usr/bin/false"))
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        try store.update { $0.agentProvider = "codex" }
        let agents = AgentSettings(location: fixture.location, searchDirectory: fixture.root)
        let schedules = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update, schedules: schedules,
                                  shortcuts: [], agents: agents, openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        defer { settings.window?.close() }

        settings.show(.assistant)
        await agents.wait()
        let first = ["CLI 기본", "Model 1", "Model 2", "Model 3", "Model 4", "Model 5"]
        try checkMenu(settings, first, selected: "CLI 기본")
        try store.update { $0.codexModel = "m5" }
        try checkMenu(settings, first, selected: "Model 5")
        try store.update { $0.codexModel = "m11" }
        try checkMenu(settings, first + ["Model 11"], selected: "Model 11")

        settings.window?.close()
        try FileManager.default.removeItem(at: catalog)
        settings.show(.assistant)
        await agents.wait()
        try checkMenu(settings, ["CLI 기본"], selected: "CLI 기본")
        func storedModel() throws -> String? {
            try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.codexModel
        }
        #expect(try storedModel() == "m11")

        settings.window?.close()
        try JSONSerialization.data(withJSONObject: ["models": Array(entries.dropFirst())]).write(to: catalog)
        settings.show(.assistant)
        await agents.wait()
        try checkMenu(settings, first, selected: "CLI 기본")
        #expect(try storedModel() == nil)

        settings.window?.close()
        try JSONSerialization.data(withJSONObject: ["models": entries]).write(to: catalog)
        settings.show(.assistant)
        await agents.wait()
        try checkMenu(settings, first, selected: "CLI 기본")
    }

    @Test func claudeMenuUsesAllCLIValuesAndPreservesTheSelectionOnFailure() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let cli = fixture.root.appending(path: "claude")
        try #"""
        #!/bin/sh
        set -eu
        case "$1" in
          --version) echo fake ;;
          auth) echo '{"loggedIn":true}' ;;
          -p)
            IFS= read -r request
            id=$(printf '%s' "$request" | plutil -extract request_id raw -o - -)
            models=$(cat "$(dirname "$0")/models.json")
            printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"models":%s}}}\n' "$id" "$models"
            ;;
          *) exit 1 ;;
        esac
        """#.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let catalog = fixture.root.appending(path: "models.json")
        let longTitle = "모델 7 Research Preview 5.5"
        var entries = (1...7).map { ["value": "v\($0)", "displayName": "모델 \($0)"] }
        entries[6]["description"] = longTitle + " \u{00B7} Extended context"
        let all = ["자동"] + entries.prefix(6).compactMap { $0["displayName"] } + [longTitle]
        try JSONEncoder().encode(entries).write(to: catalog)
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let agents = AgentSettings(location: fixture.location, searchDirectory: fixture.root)
        let schedules = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update, schedules: schedules,
                                  shortcuts: [], agents: agents, openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        defer { settings.window?.close() }
        func openSettings() async {
            settings.show(.assistant)
            await agents.wait()
        }

        await openSettings()
        let menu = try checkMenu(settings, all, selected: "자동")
        let row = try #require(menu.items.last?.view)
        #expect(row.frame.width > fixture.theme.component(.claudeMenuWidth))
        menu.performActionForItem(at: menu.indexOfItem(withTitle: longTitle))
        #expect(store.settings.selectedEngine(codexModels: []).model == "v7")
        try FileManager.default.removeItem(at: catalog)
        await openSettings()
        try checkMenu(settings, all, selected: longTitle)

        settings.window?.close()
        await openSettings()
        try checkMenu(settings, ["자동", "Fable", "Opus", "Sonnet", "Haiku"], selected: "자동")
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.agentModel == "v7")

        settings.window?.close()
        try JSONEncoder().encode([entries[0]]).write(to: catalog)
        await openSettings()
        try checkMenu(settings, ["자동", "모델 1"], selected: "자동")
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.agentModel == "auto")
        #expect(store.settings.selectedEngine(codexModels: []).model == nil)
    }

    @Test func previewHasNoInteractiveAccessibilityChildren() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let settings = SettingsCoordinator(model: SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update,
            schedules: service, shortcuts: [], openPrivacy: { _ in }), theme: fixture.theme)
        settings.allowsKeyWindows = false
        settings.show(.appearance)
        defer { settings.window?.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func preview(in view: NSView) -> NSView? {
            if view.accessibilityLabel() == "노트 미리보기" { return view }
            return view.subviews.lazy.compactMap(preview).first
        }
        let root = try #require(settings.window?.contentView)
        let image = try #require(preview(in: root))
        #expect(image.accessibilityRole() == .image)
        #expect(image.accessibilityChildren()?.isEmpty != false)
        #expect(!image.acceptsFirstResponder && !image.accessibilityPerformPress())
        #expect(image.hitTest(NSPoint(x: image.bounds.midX, y: image.bounds.midY)) == nil)
    }

    #if DEBUG
    private func elements(in root: NSView) -> [AnyObject] {
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: AnyObject) -> [AnyObject] {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return [] }
            let children = node.accessibilityChildren?() ?? []
            return [node] + children.flatMap { visit($0 as AnyObject) } + ((node as? NSView)?.subviews.flatMap { visit($0) } ?? [])
        }
        return visit(root)
    }

    @Test func appearanceHeightSegmentSavesItsChoice() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location),
                                  read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        settings.show(.appearance)
        defer { settings.window?.close() }
        let root = try #require(settings.window?.contentView)
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        model.showsHeightTip = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bubble = try #require(model.layoutFrames["info-tooltip-bubble"])
        let cardLeft = fixture.theme.component(.settingsSidebarWidth) + fixture.theme.component(.settingsBodyInset)
        #expect(bubble.minX >= cardLeft)
        #expect(bubble.maxX <= root.bounds.width - fixture.theme.component(.settingsBodyInset))
        model.showsHeightTip = false
        let choices = elements(in: root)
        #expect(choices.contains { $0.accessibilityLabel?() == "노트 창 높이" })
        #expect(choices.contains { $0.accessibilityLabel?() == "고정" })
        #expect(model.values.noteHeightMode == .fixed)
        let fit = try #require(choices.first { $0.accessibilityLabel?() == "글에 맞춤" })
        #expect(fit.accessibilityPerformPress?() == true)
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.noteHeightMode == .fitContent)
    }

    @Test func appearanceFormatSwitchUpdatesAFocusedNoteWithoutResizing() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        SettingsApplication.follow(store, theme: fixture.theme, appearanceOverride: nil, setAppearance: { _ in },
            applyDisplay: { options, _ in fixture.notePanels.displayOptions = options }, showMenuIcon: { _ in })
        fixture.notePanels.toggleFormatBar = {
            do { try store.update { $0.showsFormatBar.toggle() } }
            catch { Issue.record(error) }
        }
        let (otherID, _) = try fixture.open(NoteDraft(title: "다른 노트"))
        let (id, adapter) = try fixture.open(NoteDraft(title: "서식", body: "고를 글자"))
        adapter.editor.forcesActiveAppearance = true
        let window = try #require(fixture.notePanels.window(for: id))
        #expect(window.makeFirstResponder(adapter.view))
        let scroll = try #require(adapter.view.enclosingScrollView)
        window.contentView?.layoutSubtreeIfNeeded()
        let initial = window.frame
        let bodyHeight = scroll.frame.height
        #expect(!store.settings.showsFormatBar && adapter.isEditingBody)

        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location),
                                  read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        settings.show(.appearance)
        defer { settings.window?.close() }
        let root = try #require(settings.window?.contentView)
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let control = try #require(elements(in: root).first { $0.accessibilityLabel?() == "서식 막대 보이기"
            && $0.accessibilityRole?() == .checkBox })
        #expect(control.accessibilityPerformPress?() == true)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings.showsFormatBar)
        #expect(window.frame == initial)
        #expect(scroll.frame.height == bodyHeight - fixture.theme.shape(.chromeHeight))
        let otherMenu = try #require(fixture.notePanels.moreMenuForVerification(for: otherID))
        let hide = try #require(otherMenu.items.firstIndex { $0.title == "서식 막대 숨기기" })
        otherMenu.performActionForItem(at: hide)
        adapter.editor.selectedRange = NSRange(location: 0, length: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        #expect(!model.values.showsFormatBar)
        let switchedOff = try #require(elements(in: root).first { $0.accessibilityRole?() == .checkBox && $0.accessibilityLabel?() == "서식 막대 보이기" })
        let switchValue = (switchedOff as? NSObject)?.value(forKey: "accessibilityValue")
        #expect((switchValue as? NSNumber)?.boolValue == false, "스위치 값 \(String(describing: switchValue))")
        #expect(fixture.notePanels.moreMenuForVerification(for: id)?.item(withTitle: "서식 막대 보이기") != nil)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(scroll.frame.height == bodyHeight && window.frame == initial)
    }

    @Test func generalSidebarGripActionsAndOpeningTooltip() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let releaseAccessibility = TestAccessibility.enableForTest()
        defer { releaseAccessibility() }
        let prefs = try LibraryPreferencesStore(location: fixture.location)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: prefs, read: { SettingsValues() }, save: { _ in },
                                  schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        settings.show(.general)
        defer { settings.window?.close() }
        let root = try #require(settings.window?.contentView)
        func settle() {
            root.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        settle()
        let grip = try #require(elements(in: root).first {
            $0.accessibilityLabel?() == "순서 바꾸기" && $0.accessibilityCustomActions?()?.map(\.name) == ["아래로"]
        })
        let actions: [NSAccessibilityCustomAction] = grip.accessibilityCustomActions?() ?? []
        #expect(actions.map(\.name) == ["아래로"])
        let down = try #require(actions.first)
        #expect(down.handler?() == true)
        settle()
        #expect(prefs.value.viewOrder.first == .floating)
        #expect(model.layoutFrames["grip-오늘"]?.width == 14)
        #expect(model.layoutFrames["row-오늘"]?.height == 36)
        let window = try #require(settings.window)
        let frame = try #require(model.layoutFrames["grip-오늘"])
        let start = CGPoint(x: frame.midX, y: root.bounds.height - frame.midY)
        for (type, dy) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseDragged, 12.0),
                            (.leftMouseDragged, 36.0), (.leftMouseUp, 36.0)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: .init(x: start.x, y: start.y - dy),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
            settle()
        }
        #expect(prefs.value.viewOrder == [.floating, .all, .today, .reminders])
        model.showsOpeningTip = true
        settle()
        #expect(elements(in: root).contains { $0.accessibilityLabel?() == "끄면 맨 위의 보기에서 열어요" })
    }

    @Test func sidebarAndAccountDetailSpacing() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { SettingsValues() }, save: { _ in }, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let coordinator = SettingsCoordinator(model: model, theme: fixture.theme)
        coordinator.allowsKeyWindows = false
        coordinator.show(.appearance)
        defer { coordinator.window?.close() }
        func layout() -> [String: CGRect] {
            coordinator.window?.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            return model.layoutFrames
        }
        let sidebar = layout()
        let appearance = try #require(sidebar["모양"])
        let editor = try #require(sidebar["편집기"])
        #expect(editor.midY - appearance.midY == 28 && editor.minY - appearance.maxY == 2)
        for (status, activity): (EngineAccount.Status, EngineAccount.Activity?) in [
            (.signedOut, nil), (.signedOut, .login), (.connected, nil), (.missing, nil)
        ] {
            model.detailEngine = EngineAccount(previewing: status, activity: activity, location: fixture.location)
            model.pane = .accounts
            let frames = layout()
            let account = try #require(frames["account"])
            if status == .missing {
                let install = try #require(frames["install"])
                let heading = try #require(frames["heading"])
                let command = try #require(frames["command"])
                let guide = try #require(frames["guide"])
                #expect(install.minY - account.maxY == 12)
                #expect(heading.minY - install.minY == 12 && install.maxY - guide.maxY == 12)
                #expect(command.minX - install.minX == 12 && install.maxX - command.maxX == 12)
                #expect(command.minY - heading.maxY == 8 && guide.minY - command.maxY == 8 && command.height == 34)
            } else {
                let action = try #require(frames["action"])
                #expect(action.minY - account.maxY == 10 && action.maxX == account.maxX)
            }
        }
    }
    #endif

    @Test func fontSliderAndCalendarDefaultChoice() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let coordinator = SettingsCoordinator(model: model, theme: fixture.theme)
        coordinator.allowsKeyWindows = false
        coordinator.show(.appearance)
        let window = try #require(coordinator.window)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()
        func first<T: NSView>(_ type: T.Type, in view: NSView, where matches: (T) -> Bool = { _ in true }) -> T? {
            if let control = view as? T, matches(control) { return control }
            for child in view.subviews {
                if let found = first(type, in: child, where: matches) { return found }
            }
            return nil
        }
        let slider = try #require(first(NSSlider.self, in: root))
        #expect(slider.numberOfTickMarks == 6 && slider.minValue == 12 && slider.maxValue == 17)
        slider.integerValue = 16
        slider.sendAction(slider.action, to: slider.target)
        #expect(store.settings.bodySize == 16)
        coordinator.show(.schedule)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let button = try #require(first(NSButton.self, in: root) { $0.accessibilityLabel() == "기본 캘린더" })
        let menu = try #require(button.menu)
        #expect(menu.items.first?.title == "캘린더 앱 기본값" && menu.items.first?.state == .on)
        button.sendAction(button.action, to: button.target)
        let popup = try #require(window.childWindows?.first(where: { $0.isVisible }))
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        #expect(popup.frame.width == 210 && popup.frame.maxX - anchor.maxX == 12 && anchor.minY - popup.frame.maxY == 4)
        let surface = try #require(popup.contentView)
        let workRow = try #require(first(PickerMenuRow.self, in: surface) { $0.accessibilityLabel() == "업무" })
        #expect(workRow.window === popup && workRow.frame.height == 26 && workRow.frame.width == 200)
        let menuRows = try #require(workRow.superview).subviews.compactMap { $0 as? PickerMenuRow }
        for (previous, next) in zip(menuRows, menuRows.dropFirst()) {
            #expect(previous.frame.maxY <= next.frame.minY)
        }
        #expect(workRow.accessibilityPerformPress())
        #expect(!popup.isVisible)
        #expect(store.settings.calendarID == "work")
        menu.performActionForItem(at: 0)
        #expect(store.settings.calendarID == nil)
        for (key, chars, flags) in [(UInt16(53), "\\u{1b}", NSEvent.ModifierFlags()), (UInt16(13), "w", .command)] {
            coordinator.show(.general)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: key))
            #expect(window.performKeyEquivalent(with: event))
            #expect(!window.isVisible)
        }
    }

    @Test func statusMenuSettingsPreservesHiddenAndClosedNotes() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(preferences: try LibraryPreferencesStore(location: fixture.location), read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
        let settings = SettingsCoordinator(model: model, theme: fixture.theme)
        settings.allowsKeyWindows = false
        defer { settings.window?.close() }
        let router = AppRouter()
        router.notePanels = fixture.notePanels
        router.settingsWindow = settings
        let dispatcher = AppCommandDispatcher(router: router, notePanels: fixture.notePanels)
        let (hidden, _) = try fixture.open(NoteDraft(body: "숨김"))
        let (closed, _) = try fixture.open(NoteDraft(body: "닫힘"))
        fixture.notePanels.closeWindow(closed)
        fixture.notePanels.toggleAllHidden()
        let menu = NSMenu()
        StatusMenuBuilder(theme: fixture.theme).fill(menu, with: StatusMenuModel.entries(areNotesHidden: true)) { dispatcher.performStatusMenu($0) }
        let index = try #require(menu.items.firstIndex { $0.title == "설정" })
        menu.performActionForItem(at: index)
        #expect(settings.window?.isVisible == true)
        #expect(fixture.notePanels.areNotesHidden)
        #expect(fixture.notePanels.window(for: hidden)?.isVisible == false)
        #expect(fixture.notePanels.window(for: closed) == nil)
    }

    @Test func librarySettingsRowOpensExistingSettingsWindow() throws {
        let f = try AppFixture()
        defer { f.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: f.location.stateDirectory)
        let service = ScheduleService(notes: f.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let settings = SettingsCoordinator(model: SettingsModel(preferences: try LibraryPreferencesStore(location: f.location), read: { store.settings }, save: store.update,
            schedules: service, shortcuts: [], openPrivacy: { _ in }), theme: f.theme)
        settings.allowsKeyWindows = false
        defer { settings.window?.close() }
        let router = AppRouter()
        router.notePanels = f.notePanels
        router.settingsWindow = settings
        let library = LibraryCoordinator(theme: f.theme, notes: f.notes, spaces: try SpaceStore(location: f.location),
            windows: f.windowStates, preferences: settings.model.preferences, router: router)
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        let window = try #require(library.window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        func settingsRow(_ view: NSView) -> NSView? {
            if view.accessibilityLabel() == "설정 호버" { return view }
            return view.subviews.lazy.compactMap(settingsRow).first
        }
        let row = try #require(window.contentView.flatMap(settingsRow))
        let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        #expect(settings.window?.isVisible == true)
        settings.model.moveView(.all, to: .today)
        #expect(library.model.settings.visibleViews == [.all, .today, .floating])
        library.model.moveSidebar(.today, to: .all)
        #expect(settings.model.preferences.value.visibleViews == [.today, .all, .floating])
        let opened = try #require(settings.window)
        #expect(router.route(.openSettings) == .handled && settings.window === opened)
    }

    @Test func savedChangesReachAnOpenNoteAndLibrary() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let library = LibraryCoordinator(theme: fixture.theme, notes: fixture.notes,
            spaces: try SpaceStore(location: fixture.location), windows: fixture.windowStates,
            preferences: try LibraryPreferencesStore(location: fixture.location), router: AppRouter())
        library.allowsKeyWindows = false
        library.show()
        defer { library.close() }
        fixture.editors.follow(store)
        let (_, adapter) = try fixture.open(NoteDraft(body: "내일 회의"))
        var appearance: NSAppearance?
        var iconVisible = true
        SettingsApplication.follow(store, theme: fixture.theme, appearanceOverride: nil, setAppearance: { appearance = $0 },
            applyDisplay: { options, enabled in
                fixture.notePanels.displayOptions = options
                fixture.notePanels.recognizesDates = enabled
                library.model.displayOptions = options
            }, showMenuIcon: { iconVisible = $0 })
        let libraryBodySize = library.model.theme.nsFont(.body).pointSize
        try store.update {
            $0.appearance = "dark"
            $0.bodySize = 16
            $0.bodyLineHeight = 28
            $0.inlineCode = "plain"
            $0.checkbox = "bracket"
            $0.recognizesDates = false
            $0.scheduleDateFormat = "absolute"
            $0.showsMenuBarIcon = false
            $0.spaceDisplay = "name"
            $0.clockFormat = "twentyFourHour"
            $0.reminderDisplay = "iconOnly"
        }
        #expect(try AppSettingsStore(stateDirectory: fixture.location.stateDirectory).settings == store.settings)
        #expect(appearance?.name == .darkAqua && !iconVisible)
        #expect(library.model.theme.nsFont(.body).pointSize == libraryBodySize)
        #expect(adapter.editor.textView.font?.pointSize == 16)
        #expect(fixture.theme.lineHeight(.body) == 28)
        #expect(adapter.editor.configuration.checkboxStyle == .bracket)
        #expect(adapter.editor.configuration.inlineCodeStyle == .plain)
        #expect(!adapter.editor.configuration.recognizesDates && !fixture.notePanels.recognizesDates)
        #expect(library.model.displayOptions == fixture.notePanels.displayOptions)
        #expect(library.model.displayOptions == NoteDisplayOptions(dateFormat: .absolute, space: .name,
                                                                   reminder: .iconOnly, clock: .twentyFourHour))
        try store.update { $0.appearance = "system" }
        #expect(appearance == nil)
    }
}
