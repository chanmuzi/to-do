import AppKit
@_spi(Verification) import Editor
@testable import FloatSettings
import Library
import Models
import Scheduling
import Store
import Testing
import Theme
@testable import FloatingNotes

@Suite struct SettingsWindowTests {
    @Test func routingReusesWindowAndRequestsOnlyOnConnect() async throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let fake = FakeCalendarBridge()
        fake.accessByKind = [.event: .needsRequest, .reminder: .blocked]
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { fake })
        service.preferredID = { store.settings[idFor: $0] }
        let model = SettingsModel(read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
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

    @Test func previewHasNoInteractiveAccessibilityChildren() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let store = try AppSettingsStore(stateDirectory: fixture.location.stateDirectory)
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let settings = SettingsCoordinator(model: SettingsModel(read: { store.settings }, save: store.update,
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
    @Test func sidebarAndAccountDetailSpacing() throws {
        let fixture = try AppFixture()
        defer { fixture.cleanUp() }
        let service = ScheduleService(notes: fixture.notes, notifier: FakeReminderNotifier(), makeBridge: { FakeCalendarBridge() })
        let model = SettingsModel(read: { SettingsValues() }, save: { _ in }, schedules: service, shortcuts: [], openPrivacy: { _ in })
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
        let model = SettingsModel(read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
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
        let model = SettingsModel(read: { store.settings }, save: store.update, schedules: service, shortcuts: [], openPrivacy: { _ in })
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
        let settings = SettingsCoordinator(model: SettingsModel(read: { store.settings }, save: store.update,
            schedules: service, shortcuts: [], openPrivacy: { _ in }), theme: f.theme)
        settings.allowsKeyWindows = false
        defer { settings.window?.close() }
        let router = AppRouter()
        router.notePanels = f.notePanels
        router.settingsWindow = settings
        let library = LibraryCoordinator(theme: f.theme, notes: f.notes, spaces: try SpaceStore(location: f.location),
            windows: f.windowStates, preferences: try LibraryPreferencesStore(location: f.location), router: router)
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
