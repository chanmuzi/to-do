import AppKit
import Scheduling
import FloatSettings
import Reminders
import NotePanel
import Library
import Routing
import Store
import Theme

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var environment: AppEnvironment?
    private var router: AppRouter?
    private var notePanels: NotePanelCoordinator?
    private var schedules: ScheduleService?
    private var reminderEditor: ReminderEditorCoordinator?
    private var fakeCalendar: FakeCalendarBridge?
    private var settingsWindow: SettingsCoordinator?
    private var library: LibraryCoordinator?
    private var quickPanels: QuickPanels?
    private var editors: NoteEditorFactory?
    private var commands: AppCommandDispatcher?
    private var menuBarIcon: MenuBarIconSwitch<StatusItemController>?
    private var requestedWindowActivation = false
    private var activationFocus = ActivationFocusPolicy()
    private var hotKeys: GlobalHotKeys?
    private var pointerPresses: PointerPressMonitor?
    private var toasts: AppToasts?
    #if DEBUG
    private var debugControl: DebugControl?
    #endif

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        do {
            if let appearance = options.appearance {
                application.appearance = appearance.nsAppearance
            }
            let environment = try AppEnvironment(options: options)
            environment.theme.followAppearance(of: application)
            self.environment = environment
            environment.launchWarnings.forEach(AppLog.warning)

            let router = AppRouter()
            router.activateApp = { [weak self] in
                guard !application.isActive else { return }
                self?.requestedWindowActivation = true
                if !NSRunningApplication.current.activate(options: []) {
                    self?.requestedWindowActivation = false
                }
            }
            // 본문은 Markdown 편집기(Editor 모듈)다. 노트 창은 편집기를 모르고, 여기서 어댑터로 잇는다.
            let editors = NoteEditorFactory(windowStates: environment.windowStates, log: AppLog.warning)
            // 체크박스 모양과 인라인 코드 글자색은 저장된 설정을 따른다(바뀌면 떠 있는 편집기에 바로 반영).
            editors.follow(environment.settings)
            let notePanels = NotePanelCoordinator(
                theme: environment.theme, notes: environment.notes, windowStates: environment.windowStates,
                spaces: environment.spaces, router: router, makeBodyEditor: editors.makeEditor,
                log: AppLog.warning
            )
            #if DEBUG
            if options.debugIsPassive {
                notePanels.refuseKeyWindowsForVerification()
                // 확인용 실행은 사용자가 쓰는 앱을 뒤로 보내지 않는다.
                router.activateApp = {}
            }
            #endif
            router.notePanels = notePanels
            let reminderEditor = ReminderEditorCoordinator(notes: environment.notes, theme: environment.theme)
            #if DEBUG
            reminderEditor.allowsKeyWindows = !options.debugIsPassive
            #endif
            self.reminderEditor = reminderEditor
            router.reminders = reminderEditor
            let notifier: any ReminderNotifier
            let makeBridge: @MainActor () -> any CalendarBridge
            if options.usesFakeCalendar {
                let fake = FakeCalendarBridge(sampleEventsAt: Date())
                fakeCalendar = fake
                notifier = FakeReminderNotifier()
                makeBridge = { fake }
            } else {
                let system = SystemReminderNotifier()
                system.openNote = { [weak router] id in router?.route(.openNote(id)) }
                notifier = system
                makeBridge = { EventKitBridge() }
            }
            let schedules = ScheduleService(notes: environment.notes, notifier: notifier,
                                            makeBridge: makeBridge, log: AppLog.warning)
            schedules.preferredID = { [settings = environment.settings] in settings.settings[idFor: $0] }
            try schedules.start()
            self.schedules = schedules
            reminderEditor.calendarChoices = { [weak schedules] in schedules?.calendarChoices($0) ?? [] }
            reminderEditor.destination = { [weak schedules] item in schedules?.destination(for: item) }
            let inlineWriter = InlineScheduleWriter(notes: environment.notes, service: schedules)
            editors.onAcceptDate = { id, request in try inlineWriter.accept(request, in: id) }
            editors.onDateError = { AppLog.warning("본문 예정 저장 실패: \($0)") }
            notePanels.onAcceptTitleDate = { id, request in try inlineWriter.accept(request, in: id) }
            reminderEditor.onSave = { [weak schedules] id, itemID, isNew in
                schedules?.register(id, itemID: itemID, requestPermission: isNew)
            }
            router.onScheduleCreated = { [weak schedules] id, itemID in
                schedules?.register(id, itemID: itemID, requestPermission: true)
            }
            // 빠른 캡처와 노트 찾기. 노트 창과 같은 창 상태를 넘겨 "떠 있는 노트"와 핀이 보이게 한다.
            let quickPanels = QuickPanels(
                theme: environment.theme, notes: environment.notes, spaces: environment.spaces,
                windowStates: environment.windowStates, router: router, notePanels: notePanels,
                log: AppLog.warning
            )
            quickPanels.capture.onScheduleCreated = router.onScheduleCreated
            #if DEBUG
            if options.debugIsPassive { quickPanels.refuseKeyWindowsForVerification() }
            #endif
            let library = LibraryCoordinator(theme: environment.theme, notes: environment.notes,
                spaces: environment.spaces, windows: environment.windowStates,
                preferences: try LibraryPreferencesStore(location: environment.location), router: router)
            library.model.readEvents = { [weak schedules] in schedules?.events(in: $0) ?? [] }
            library.model.linkedDestination = { [weak schedules] in schedules?.destination(for: $0) }
            library.model.openCalendarEvent = { [weak library, fakeCalendar] event in
                guard let url = event.calendarURL else {
                    library?.model.error = "캘린더 일정에 연결된 식별자가 없습니다"
                    return
                }
                if let fakeCalendar { fakeCalendar.open(url); return }
                guard let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
                    library?.model.error = "캘린더 일정을 열 수 없습니다"
                    return
                }
                NSWorkspace.shared.open([url], withApplicationAt: calendarApp, configuration: .init()) { _, error in
                    if let error { Task { @MainActor in library?.model.error = error.localizedDescription } }
                }
            }
            let settingsWindow = makeSettingsWindow(environment: environment, schedules: schedules)
            self.settingsWindow = settingsWindow
            router.settingsWindow = settingsWindow
            schedules.calendarChanged = { [weak self, weak library, weak reminderEditor] in
                self?.refreshSettingsCalendars()
                if let reminderEditor { reminderEditor.model?.destination = reminderEditor.destination }
                if library?.window?.isVisible == true { library?.model.refreshCalendar() }
            }
            library.beforeMove = { [weak notePanels] in notePanels?.flushPendingEdits() }
            #if DEBUG
            library.allowsKeyWindows = !options.debugIsPassive
            #endif
            router.library = library
            self.library = library
            refreshSettingsCalendars()
            SettingsApplication.follow(environment.settings, theme: environment.theme,
                appearanceOverride: options.appearance, setAppearance: { NSApp.appearance = $0 },
                applyDisplay: { [weak notePanels, weak library, weak reminderEditor] display, recognizesDates in
                    notePanels?.recognizesDates = recognizesDates
                    notePanels?.displayOptions = display
                    library?.model.displayOptions = display
                    reminderEditor?.displayOptions = display
                    if let reminderEditor { reminderEditor.model?.destination = reminderEditor.destination }
                }, showMenuIcon: { [weak self] shown in
                    guard let self else { return }
                    menuBarIcon?.apply(shown: options.menuBarIconOverride ?? shown)
                })
            router.quickPanels = quickPanels
            self.router = router
            self.notePanels = notePanels
            self.quickPanels = quickPanels
            self.editors = editors

            let commands = AppCommandDispatcher(router: router, notePanels: notePanels)
            commands.changeBodySize = { try $0.apply(to: environment.settings, theme: environment.theme) }
            commands.closeQuickPanel = { [unowned quickPanels] in quickPanels.closeVisiblePanel() }
            self.commands = commands
            // 휴지통으로 보낸 뒤와 캡처한 뒤의 짧은 알림(D-041).
            toasts = AppToasts(
                presenter: ToastPresenter(theme: environment.theme), notePanels: notePanels,
                capture: quickPanels.capture, notes: environment.notes, router: router,
                undoTrash: { [unowned commands] in commands.undoOrRestoreTrash(nil) }
            )
            // 노트 찾기를 닫은 누름과 그 누름이 보낸 "노트 찾기 열기"를 한데 묶는다(`QuickPanels`).
            pointerPresses = PointerPressMonitor(
                began: { [unowned quickPanels] in quickPanels.pointerPressBegan() },
                ended: { [unowned quickPanels] in quickPanels.pointerPressEnded() }
            )
            let shortcuts = ShortcutTable.standard
            application.mainMenu = MainMenu.make(
                appName: Self.displayName, table: shortcuts, dispatcher: commands
            )
            menuBarIcon = makeMenuBarIconSwitch(environment, notePanels, commands)
            // 꺼 두었으면 아이콘 파일을 읽지 않는다. 켰는데 읽지 못하면 경고만 남기고 아이콘 없이 간다.
            menuBarIcon?.apply(
                shown: options.menuBarIconOverride ?? environment.settings.settings.showsMenuBarIcon
            )
            registerGlobalHotKeys(shortcuts, commands)
            // 떠 있던 노트가 없으면 닫은 노트를 찾는 주된 길인 라이브러리를 연다.
            if notePanels.restoreOpenNotes().isEmpty { library.show() }
            #if DEBUG
            try startDebugging(router: router, notePanels: notePanels)
            #endif
            activationFocus.launchFinished(at: ProcessInfo.processInfo.systemUptime)
        } catch {
            presentLaunchFailure(error)
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        let target = requestedWindowActivation || router?.isRouting == true || NSEvent.pressedMouseButtons != 0
            || NSApp.modalWindow != nil || quickPanels?.isAnyVisible == true
        requestedWindowActivation = false
        if activationFocus.shouldShowLibrary(activatedAt: ProcessInfo.processInfo.systemUptime, hasExplicitTarget: target) {
            library?.bringForward()
        }
    }

    /// 다른 프로그램이 제자리에서 고친 파일도 앞으로 올 때 다시 읽는다.
    func applicationDidBecomeActive(_ notification: Notification) {
        refreshSettingsCalendars()
        do {
            try environment?.notes.refresh()
        } catch {
            AppLog.warning("노트 폴더를 다시 읽지 못했습니다: \(error)")
        }
    }

    /// 끝내기 전에 미뤄 둔 저장을 모두 쓴다. 못 쓴 노트가 있으면 이름을 보여 주고 끝낼지 묻는다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let notes = environment?.notes else { return .terminateNow }
        // 편집기가 아직 알리지 않은 글과 고치던 제목을 먼저 받는다.
        notePanels?.flushPendingEdits()
        flushWindowStates()
        do {
            try notes.flushPendingSaves()
            // 아무것도 적지 않은 노트는 남기지 않는다(D-040). 다 쓴 뒤에만 본다.
            if notePanels?.deleteBlankNotes().isEmpty == false { flushWindowStates() }
            return .terminateNow
        } catch {
            AppLog.warning("끝내기 전에 저장하지 못했습니다: \(error)")
            return UnsavedNotesAlert.confirmQuit(after: error) ? .terminateNow : .terminateCancel
        }
    }

    /// 한데 모아 쓰려고 미뤄 둔 창 상태를 쓴다. 쓰지 못해도 끝내기를 막지 않는다(노트의 글이 아니다).
    private func flushWindowStates() {
        do {
            try environment?.windowStates.flush()
        } catch {
            AppLog.warning("끝내기 전에 창 상태를 저장하지 못했습니다: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        schedules?.stop()
        reminderEditor?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock, Spotlight의 재열기는 라이브러리 한 창만 대상으로 한다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        library?.bringForward()
        return false
    }

    // MARK: - 메뉴 막대 아이콘과 Dock 메뉴

    /// 메뉴 막대 아이콘을 보이거나 감추고 설정에 적는다(설정 화면이 부른다). 감춰도 같은 항목이 Dock 메뉴와
    /// 앱 메뉴에 있고, 전역 단축키도 그대로다.
    /// 본문 편집기의 표시 방식(체크박스 모양, 인라인 코드 글자색)을 적는다. 떠 있는 편집기에 곧바로 반영된다.
    func setEditorOptions(_ options: NoteEditorOptions) {
        do {
            try environment?.settings.update { options.write(to: &$0) }
        } catch {
            AppLog.warning("편집기 표시 설정을 저장하지 못했습니다: \(error)")
        }
    }

    func setMenuBarIconShown(_ shown: Bool) {
        do {
            try environment?.settings.update { $0.showsMenuBarIcon = shown }
        } catch {
            AppLog.warning("메뉴 막대 아이콘 설정을 저장하지 못했습니다: \(error)")
        }

    }

    private func makeMenuBarIconSwitch(
        _ environment: AppEnvironment, _ notePanels: NotePanelCoordinator, _ commands: AppCommandDispatcher
    ) -> MenuBarIconSwitch<StatusItemController> {
        MenuBarIconSwitch(
            loadIcon: MenuBarIcon.load,
            makeItem: { [unowned notePanels, unowned commands] icon in
                StatusItemController(
                    theme: environment.theme, icon: icon,
                    areNotesHidden: { notePanels.areNotesHidden },
                    perform: { commands.performStatusMenu($0) }
                )
            },
            warn: AppLog.warning
        )
    }

    /// Dock 아이콘을 길게 누르거나 오른쪽으로 눌렀을 때의 메뉴. 메뉴 막대 메뉴와 같은 항목이다.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let notePanels, let commands else { return nil }
        return DockMenu.make(areNotesHidden: notePanels.areNotesHidden) { [unowned commands] in
            commands.performStatusMenu($0)
        }
    }

    // MARK: - 켤 때

    /// 메뉴에 쓰는 지역화된 앱 이름(`InfoPlist.strings`의 "Float").
    /// object(forInfoDictionaryKey:)는 지역화 값을 우선한다. SwiftPM 실행, 테스트에는 Float를 쓴다.
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Float"
    }

    /// "어디서나" 쓰는 단축키를 등록한다. 여는 화면이 아직 없는 동작의 키는 등록하지 않는다
    /// (`AppCommand.isConnected`). 다른 앱이 쓰는 키는 등록되지 않는다. 숨기지 않고 경고로 남긴다
    /// (설정 화면이 생기면 `GlobalHotKeys.failures`로 그 자리에서 알린다).
    private func registerGlobalHotKeys(_ table: ShortcutTable, _ commands: AppCommandDispatcher) {
        #if DEBUG
        guard !options.debugSkipsHotKeys else { return }
        #endif
        let hotKeys = GlobalHotKeys(registrar: CarbonHotKeyRegistrar()) { [unowned commands] in
            commands.perform($0)
        }
        hotKeys.register(table).map(\.warning).forEach(AppLog.warning)
        self.hotKeys = hotKeys
    }

    #if DEBUG
    private func startDebugging(router: AppRouter, notePanels: NotePanelCoordinator) throws {
        options.debugHover.forEach { notePanels.setHoverOverride(true, for: $0) }
        guard let directory = options.debugControlDirectory else { return }
        guard let editors, let commands, let quickPanels else { return }
        let control = DebugControl(
            session: try DebugControlSession.start(in: directory), router: router, notePanels: notePanels,
            quickPanels: DebugQuickPanels(panels: quickPanels),
            editors: editors, commands: commands, hotKeys: hotKeys, isPassive: options.debugIsPassive,
            statusItem: { [unowned self] in menuBarIcon?.item },
            dockMenu: { [unowned self] in applicationDockMenu(NSApplication.shared) },
            setMenuBarIconShown: { [unowned self] in setMenuBarIconShown($0) }
        )
        control.settingsWindow = settingsWindow
        control.reminderEditor = reminderEditor
        control.fakeCalendar = fakeCalendar
        control.library = library
        control.setScheduleDateFormat = { [weak self] value in
            do { try self?.environment?.settings.update { $0.scheduleDateFormat = value } }
            catch { AppLog.warning("표시 설정 저장 실패: \(error)") }
        }
        control.simulateActivation = { [weak self] in
            self?.applicationWillBecomeActive(Notification(name: NSApplication.willBecomeActiveNotification))
            self?.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        }
        control.reopen = { [weak self] in _ = self?.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false) }
        control.toastWindow = { [unowned self] in toasts?.presenter.window }
        control.toastAction = { [unowned self] in toasts?.presenter.performAction() }
        control.start()
        debugControl = control
    }
    #endif

    private func makeSettingsWindow(environment: AppEnvironment, schedules: ScheduleService) -> SettingsCoordinator {
        let store = environment.settings
        let table = ShortcutTable.standard
        let sections = ShortcutGroup.allCases.map { group in
            let title = group == .aiPanel ? "AI 패널 (예정)" : group == .global ? "어디서나" : group.rawValue
            return ShortcutSection(title, rows: table.entries(in: group).map { entry in
                let action = entry.command?.isConnected == false ? entry.action + " (예정)" : entry.action
                return (action, entry.keyLabels.joined(separator: group == .markdownInput ? " 또는 " : " "))
            })
        }
        let model = SettingsModel(read: { store.settings }, save: store.update, schedules: schedules,
                                  shortcuts: sections) { [usesFake = options.usesFakeCalendar] kind in
            guard !usesFake else { return }
            let anchor = kind == .event ? "Privacy_Calendars" : "Privacy_Reminders"
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
                NSWorkspace.shared.open(url)
            }
        }
        let coordinator = SettingsCoordinator(model: model, theme: environment.theme)
        #if DEBUG
        coordinator.allowsKeyWindows = !options.debugIsPassive
        #endif
        return coordinator
    }

    private func refreshSettingsCalendars() {
        guard let settingsWindow, let values = environment?.settings.settings,
              settingsWindow.window?.isVisible == true || values.calendarID != nil || values.reminderListID != nil else { return }
        settingsWindow.model.refreshCalendars()
    }

    private func presentLaunchFailure(_ error: Error) {
        AppLog.warning("앱을 시작하지 못했습니다: \(error)")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "앱을 시작하지 못했습니다"
        alert.informativeText = "\(error)"
        alert.runModal()
        exit(1)
    }
}
