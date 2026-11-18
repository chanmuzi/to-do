import AppKit
import FloatSettings
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
        #expect(library.model.theme.tokens.textStyle(.body).size == 16)
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
