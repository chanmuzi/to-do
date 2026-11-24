import AppKit
import Agent
import AgentRunner
import Models
import Carbon
import OSLog
import Scheduling
import FloatSettings
import Reminders
import NotePanel
import Library
import Routing
import Store
import Theme

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let activationLog = Logger(subsystem: "local.floating-notes", category: "activation")
    private let options: LaunchOptions
    private var environment: AppEnvironment?
    private var router: AppRouter?
    private var notePanels: NotePanelCoordinator?
    private var schedules: ScheduleService?
    private var reminderEditor: ReminderEditorCoordinator?
    private var fakeCalendar: FakeCalendarBridge?
    private var settingsWindow: SettingsCoordinator?
    private var library: LibraryCoordinator?
    private var agentCorner: AgentCorner?
    private var proposalController: TodoProposalController?
    private var instructionEditor: InstructionEditor?
    private var instructionStore: AgentStore?
    private var requests: AgentRequestCoordinator?
    private var quickPanels: QuickPanels?
    private var editors: NoteEditorFactory?
    private var commands: AppCommandDispatcher?
    private var menuBarIcon: MenuBarIconSwitch<StatusItemController>?
    private var requestedWindowActivation = false
    private var activationFocus = ActivationFocusPolicy()
    private var hotKeys: GlobalHotKeys?
    private var pointerPresses: PointerPressMonitor?
    /// 늦게 오는 누름을 기다리는 동안 미뤄 둔 라이브러리 올리기.
    private var pendingLibraryRaise: DispatchWorkItem?
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
            let store = AgentStore(location: environment.location)
            instructionStore = store
            let agent = AgentWindowCoordinator(store: store,
                                               theme: environment.theme, warning: AppLog.warning)
            #if DEBUG
            agent.allowsKeyWindows = !options.debugIsPassive
            #endif
            router.agent = agent
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
                system.openAgent = { [weak self] provider in self?.settingsWindow?.showAgent(provider) }
                system.openConversation = { [weak router] id in router?.openBarConversation(id, source: "notification") }
                system.installDelegate()
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
            notePanels.toggleFormatBar = { [settings = environment.settings] in
                do { try settings.update { $0.showsFormatBar.toggle() } }
                catch { RouteFailureAlert.present(title: "서식 막대 설정을 저장하지 못했습니다", error: error) }
            }
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
            library.model.updateOpenWindowPin = { [weak notePanels] id, pinned in
                notePanels?.setPinned(pinned, for: id)
            }
            let instructionEditor = InstructionEditor(theme: environment.theme, store: store)
            self.instructionEditor = instructionEditor
            library.model.instructionView = instructionEditor.editor.view
            library.model.openInstructions = instructionEditor.open
            library.model.flushInstructions = store.flushInstructions
            store.instructionSaveFailed = { [weak library] in library?.model.error = $0.localizedDescription }
            router.connectHistory(library.model, agent: agent)
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
            let settingsWindow = makeSettingsWindow(environment: environment, schedules: schedules, preferences: library.model.preferences)
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
            let corner = AgentCorner(theme: environment.theme, agent: agent, router: router, notes: notePanels)
            agentCorner = corner
            SettingsApplication.follow(environment.settings, theme: environment.theme,
                appearanceOverride: options.appearance, setAppearance: { NSApp.appearance = $0 },
                applyDisplay: { [weak notePanels, weak library, weak reminderEditor] display, recognizesDates in
                    notePanels?.recognizesDates = recognizesDates
                    notePanels?.displayOptions = display
                    library?.model.displayOptions = display
                    reminderEditor?.displayOptions = display
                    if let reminderEditor { reminderEditor.model?.destination = reminderEditor.destination }
                }, showCornerAgent: corner.setEnabled, showMenuIcon: { [weak self] shown in
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
            try connectRequests(environment, router: router, agent: agent, panels: quickPanels, notes: notePanels)
            // 노트 찾기를 닫은 누름과 그 누름이 보낸 "노트 찾기 열기"를 한데 묶는다(`QuickPanels`).
            pointerPresses = PointerPressMonitor(
                began: { [unowned quickPanels] in quickPanels.pointerPressBegan() },
                ended: { [unowned quickPanels] in quickPanels.pointerPressEnded() },
                inactiveWindowPress: { [weak self] window, time in
                    guard window !== self?.library?.window else { return }
                    self?.activationFocus.windowPressedWhileInactive(at: time)
                },
                windowPress: { [weak self] window in
                    guard let self, window !== self.library?.window else { return }
                    self.latePressArrived()
                }
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
        let carbon = ActivationFocusPolicy.carbonTarget(GetCurrentEvent())
        let appKit = ActivationFocusPolicy.carbonTarget(NSApp.currentEvent?.eventRef.map { EventRef($0) })
        let pointer = ActivationPointer(library: library?.window)
        let requested = requestedWindowActivation
        requestedWindowActivation = false
        let routing = router?.isRouting == true
        let modal = NSApp.modalWindow != nil
        let quick = quickPanels?.isAnyVisible == true
        let decision = activationFocus.decide(at: ProcessInfo.processInfo.systemUptime, explicitTarget: requested || routing || modal || quick,
                                              carbon: carbon, appKit: appKit, window: pointer.window,
                                              mouseAge: pointer.mouseAge, keyAge: pointer.keyAge)
        let pending = decision.pendingAge.map { String(format: "%.3f", $0) } ?? "none"
        let message = "requested=\(requested) routing=\(routing) modal=\(modal) quick=\(quick)"
            + " carbon=\(carbon.rawValue) appKitEvent=\(appKit.rawValue) pendingAge=\(pending) window=\(pointer.window.rawValue)"
            + String(format: " mouseAge=%.3f keyAge=%.3f", pointer.mouseAge, pointer.keyAge)
            + " decision=\(decision.reason.rawValue) reused=\(decision.reused)"
        activationLog.notice("\(message, privacy: .public)")
        guard decision.reason == .showLibrary else { return }
        guard ActivationFocusPolicy.waitsForLatePress(window: pointer.window) else {
            library?.bringForward()
            return
        }
        // 누른 채로 활성화됐으면 그 창을 누른 것이다.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            activationFocus.adoptLatePress()
            activationLog.notice("late-press decision=localPress source=buttonDown")
            return
        }
        pendingLibraryRaise?.cancel()
        let raise = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingLibraryRaise = nil
            guard NSApp.isActive else { return }
            activationLog.notice("late-press decision=showLibrary source=timeout")
            library?.bringForward()
        }
        pendingLibraryRaise = raise
        DispatchQueue.main.asyncAfter(deadline: .now() + ActivationFocusPolicy.latePressWait, execute: raise)
    }

    /// 활성화 알림 뒤에 Float 창(라이브러리 밖)의 누름이 전달됐다. 기다리던 라이브러리 올리기를 거둔다.
    private func latePressArrived() {
        guard let raise = pendingLibraryRaise else { return }
        raise.cancel()
        pendingLibraryRaise = nil
        activationFocus.adoptLatePress()
        activationLog.notice("late-press decision=localPress source=event")
    }

    func applicationDidResignActive(_ notification: Notification) {
        pendingLibraryRaise?.cancel()
        pendingLibraryRaise = nil
        activationFocus.didResignActive()
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
        notePanels?.saveReadingPositions()
        flushWindowStates()
        do {
            try instructionStore?.flushInstructions()
            try notes.flushPendingSaves()
            try router?.agent?.flushFailedDrafts()
            // 아무것도 적지 않은 노트는 남기지 않는다(D-040). 다 쓴 뒤에만 본다.
            if notePanels?.deleteBlankNotes().isEmpty == false { flushWindowStates() }
        } catch {
            AppLog.warning("끝내기 전에 저장하지 못했습니다: \(error)")
            guard UnsavedNotesAlert.confirmQuit(after: error) else { return .terminateCancel }
        }
        let agents = settingsWindow?.model.agents
        if requests?.task != nil || agents?.hasActiveTasks == true {
            agents?.cancel()
            Task {
                await requests?.shutdown()
                await agents?.wait()
                do { try router?.agent?.flushFailedDrafts() }
                catch {
                    if !UnsavedNotesAlert.confirmQuit(after: error) {
                        requests?.continueAfterCancelledQuit()
                        sender.reply(toApplicationShouldTerminate: false)
                        return
                    }
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
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
        activationLog.notice("reopen decision=showLibrary")
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

    /// 메뉴 이름은 앱 묶음에서 읽고, SwiftPM 실행과 테스트에서는 Float를 쓴다.
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
        control.agent = router.agent
        control.instructionEditor = instructionEditor
        control.proposals = proposalController
        control.agentCorner = agentCorner
        control.theme = environment?.theme
        control.settingsWindow = settingsWindow
        control.reminderEditor = reminderEditor
        control.fakeCalendar = fakeCalendar
        control.library = library
        control.setScheduleDateFormat = { [weak self] value in
            do { try self?.environment?.settings.update { $0.scheduleDateFormat = value } }
            catch { AppLog.warning("표시 설정 저장 실패: \(error)") }
        }
        control.simulateActivation = { [weak self] repeatLocalPress in
            guard let self else { return }
            applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
            let willActivate = Notification(name: NSApplication.willBecomeActiveNotification)
            if repeatLocalPress {
                activationFocus.windowPressedWhileInactive(at: ProcessInfo.processInfo.systemUptime)
                applicationWillBecomeActive(willActivate)
            }
            applicationWillBecomeActive(willActivate)
            applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        }
        control.reopen = { [weak self] in _ = self?.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false) }
        control.toastWindow = { [unowned self] in toasts?.presenter.window }
        control.toastAction = { [unowned self] in toasts?.presenter.performAction() }
        control.start()
        debugControl = control
    }
    #endif

    private func agentDirectory(_ environment: AppEnvironment) -> URL? {
        #if DEBUG
        if let bin = options.debugAgentDirectory { return bin }
        if options.debugIsPassive { return environment.location.stateDirectory.appending(path: "verification-bin") }
        #endif
        return nil
    }

    private func connectRequests(_ environment: AppEnvironment, router: AppRouter, agent: AgentWindowCoordinator,
                                 panels: QuickPanels, notes: NotePanelCoordinator) throws {
        try agent.restore()
        var execution = AgentExecution(location: environment.location, directory: agentDirectory(environment), instructionStore: instructionStore)
        execution.supportedEfforts = settingsWindow?.model.supportedEfforts
        execution.noteContext = {
            AgentNoteContext(windows: Dictionary(uniqueKeysWithValues: environment.windowStates.all.map {
                ($0.key.rawValue, .init($0.value))
            }), spaces: Dictionary(uniqueKeysWithValues: environment.spaces.spaces.map { ($0.id.rawValue, $0.name) }),
            archiveCutoff: environment.notes.archiveCutoff)
        }
        #if DEBUG
        if options.debugIsPassive { execution.notifications = AgentExpiryNotifications(notifier: VerificationExpiryNotifier()) }
        #endif
        let modelSettings = settingsWindow?.model
        let coordinator = AgentRequestCoordinator(choice: {
            let settings = environment.settings.settings
            let provider = AgentProvider(rawValue: settings.agentProvider) ?? .claude
            let model = provider == .codex ? settings.codexModel : AgentEngine.claude(settings.agentModel).model
            return .init(provider: provider, model: model, effort: modelSettings?.selectedEffort)
        }, note: { file in
            guard let item = try? environment.notes.list().notes.first(where: { $0.id.rawValue + ".md" == file }) else { return nil }
            return (item.id, item.title.isEmpty ? "제목 없음" : item.title)
        }, execute: execution.run)
        let inbox = ProposalInbox(location: environment.location)
        coordinator.inbox = inbox
        for draft in agent.drafts {
            try draft.recoverProposals(notes: environment.notes)
            for request in draft.conversation.requests {
                try inbox.remove(request.runID)
            }
        }
        coordinator.prepareRecovery = execution.prepareRecovery
        requests = coordinator
        router.traceActivation = { [activationLog] event in activationLog.notice("\(event, privacy: .public)") }
        panels.traceActivation = router.traceActivation
        agent.onClose = { [weak router] in router?.traceActivation("agent-close") }
        agent.present = { [weak router] draft, source in router?.showAgent(draft, source: source) }
        let proposals = TodoProposalController(agent: agent, notes: environment.notes, panels: notes, theme: environment.theme, router: router)
        proposalController = proposals
        proposals.showToast = { [weak self] message, action, perform in
            self?.toasts?.presenter.show(.init(kind: "proposal", message: message, actionTitle: action), on: self?.toasts?.pointerScreen(), action: perform)
        }
        proposals.showError = { [weak self] message in
            self?.toasts?.presenter.show(.init(kind: "proposal-error", message: message, actionTitle: "닫기"), on: self?.toasts?.pointerScreen()) {}
        }
        agent.openProposal = { [weak proposals] in proposals?.open($0, source: "conversation") }
        if let library { proposals.connect(library.model) }
        proposals.start()
        agent.send = { _ = coordinator.submit($0, text: $0.conversation.draft) }
        agent.finishDeletion = coordinator.finishDeletion
        agent.stopBeforeDelete = coordinator.stopBeforeDelete
        agent.retry = coordinator.retry
        agent.sendAll = coordinator.sendAll
        agent.sendNow = coordinator.sendNow
        agent.openNote = { [weak router] id in router?.route(.openNote(id)) }
        agent.titleForNote = { (try? environment.notes.load($0))?.title }
        agent.chooseTarget = { [weak panels, weak router] draft in
            panels?.toggleBrowse(anchor: nil)
            panels?.browse.pickTarget = { id in
                if !draft.conversation.targets.contains(id) { draft.change { $0.targets.append(id) } }
                router?.showAgent(draft, source: "target")
            }
        }
        if let model = settingsWindow?.model {
            panels.capture.modelPicker = { model.inlinePicker(theme: environment.theme, visible: true) }
            agent.modelPicker = { model.inlinePicker(theme: environment.theme, visible: $0, lineSpace: $1) }
        }
        let bar = BarRequestFlow(agent: agent, requests: coordinator)
        if options.usesFakeCalendar { bar.deliver = { _ in true } }
        panels.capture.recentRequest = { bar.recent }
        panels.capture.openRecent = { [weak router, weak panels] id in
            router?.openBarConversation(id, source: "bar-recent", screen: panels?.capture.screen)
        }
        panels.capture.onRequest = { [weak router, weak panels] text in
            guard let draft = bar.submit(text) else { return false }
            router?.showAgent(draft, source: "bar", screen: panels?.capture.screen, reuseForBar: true)
            return true
        }
        coordinator.openSettings = { [weak self] in self?.settingsWindow?.showAgent($0) }
        coordinator.progress = { [weak self, weak coordinator] draft, request in
            guard draft.conversation.barRequestID != request.id else { return }
            let face = request.face
            self?.toasts?.presenter.show(.init(kind: "agent-working", message: face.rawValue, actionTitle: "취소", face: face),
                                         on: self?.toasts?.pointerScreen()) { coordinator?.task?.cancel() }
        }
        coordinator.finished = { [weak self, weak router] draft, request in
            if draft.conversation.barRequestID == request.id {
                bar.finished(draft, request)
                return
            }
            let success = request.status == .completed
            var message = success ? draft.conversation.completionMessage(for: request)
                : request.failure ?? "막혔어요"
            if let reset = request.resumeTime { message += ". " + reset + "부터 다시 돼요" }
            self?.toasts?.presenter.show(.init(kind: "agent", message: message, actionTitle: success ? "보기" : "다시 시도",
                                               face: success ? .done : .blocked),
                                         on: self?.toasts?.pointerScreen()) { [weak self] in
                if let id = request.proposals.first?.id, success { self?.proposalController?.open(id, source: "toast"); return }
                router?.showAgent(draft, source: "toast")
                if !success { self?.requests?.retry(draft, id: request.id) }
            }
        }
        coordinator.restore(agent.drafts)
    }

    private func makeSettingsWindow(environment: AppEnvironment, schedules: ScheduleService, preferences: LibraryPreferencesStore) -> SettingsCoordinator {
        let store = environment.settings
        let table = ShortcutTable.standard
        let groups: [ShortcutGroup] = [.global, .noteWindow, .capture, .browse, .library, .editing, .agent, .markdownInput]
        let sections = groups.map { group in
            let title = group == .global ? "어디서나" : group.rawValue
            return ShortcutSection(title, rows: table.entries(in: group).map { entry in
                let action = entry.command?.isConnected == false ? entry.action + " (예정)" : entry.action
                switch entry.keys {
                case .chords(let chords): return (action, chords.map { $0.labels.joined() })
                case .typed(let labels): return (action, labels)
                }
            })
        }
        let agents = AgentSettings(location: environment.location, searchDirectory: agentDirectory(environment))
        let model = SettingsModel(preferences: preferences, read: { store.settings }, save: store.update, schedules: schedules,
                                  shortcuts: sections, agents: agents) { [usesFake = options.usesFakeCalendar] kind in
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
