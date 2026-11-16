import AppKit
import NotePanel
import Routing
import Store
import Theme

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var environment: AppEnvironment?
    private var router: AppRouter?
    private var notePanels: NotePanelCoordinator?
    private var quickPanels: QuickPanels?
    private var editors: NoteEditorFactory?
    private var commands: AppCommandDispatcher?
    private var menuBarIcon: MenuBarIconSwitch<StatusItemController>?
    private var fallbackNote: FallbackNotePresenter?
    private var activationFocus = ActivationFocusPolicy()
    private var hotKeys: GlobalHotKeys?
    private var pointerPresses: PointerPressMonitor?
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
            // 본문은 Markdown 편집기(Editor 모듈)다. 노트 창은 편집기를 모르고, 여기서 어댑터로 잇는다.
            let editors = NoteEditorFactory(windowStates: environment.windowStates, log: AppLog.warning)
            let notePanels = NotePanelCoordinator(
                theme: environment.theme, notes: environment.notes, windowStates: environment.windowStates,
                spaces: environment.spaces, router: router, makeBodyEditor: editors.makeEditor,
                log: AppLog.warning
            )
            #if DEBUG
            if options.debugIsPassive { notePanels.refuseKeyWindowsForVerification() }
            #endif
            router.notePanels = notePanels
            // 빠른 캡처와 노트 찾기. 노트 창과 같은 창 상태를 넘겨 "떠 있는 노트"와 핀이 보이게 한다.
            let quickPanels = QuickPanels(
                theme: environment.theme, notes: environment.notes, spaces: environment.spaces,
                windowStates: environment.windowStates, router: router, notePanels: notePanels,
                log: AppLog.warning
            )
            #if DEBUG
            if options.debugIsPassive { quickPanels.refuseKeyWindowsForVerification() }
            #endif
            router.quickPanels = quickPanels
            self.router = router
            self.notePanels = notePanels
            self.quickPanels = quickPanels
            self.editors = editors

            let commands = AppCommandDispatcher(router: router, notePanels: notePanels)
            commands.closeQuickPanel = { [unowned quickPanels] in quickPanels.closeVisiblePanel() }
            self.commands = commands
            // 노트 찾기를 닫은 누름과 그 누름이 보낸 "노트 찾기 열기"를 한데 묶는다(`QuickPanels`).
            pointerPresses = PointerPressMonitor(
                began: { [unowned quickPanels] in quickPanels.pointerPressBegan() },
                ended: { [unowned quickPanels] in quickPanels.pointerPressEnded() }
            )
            let shortcuts = ShortcutTable.standard
            application.mainMenu = MainMenu.make(
                appName: ProcessInfo.processInfo.processName, table: shortcuts, dispatcher: commands
            )
            menuBarIcon = makeMenuBarIconSwitch(environment, notePanels, commands)
            // 꺼 두었으면 아이콘 파일을 읽지 않는다. 켰는데 읽지 못하면 경고만 남기고 아이콘 없이 간다.
            menuBarIcon?.apply(
                shown: options.menuBarIconOverride ?? environment.settings.settings.showsMenuBarIcon
            )
            registerGlobalHotKeys(shortcuts, commands)
            let fallbackNote = FallbackNotePresenter(
                notes: environment.notes, notePanels: notePanels, warn: AppLog.warning,
                presentFailure: { RouteFailureAlert.present(title: $0, error: $1) }
            )
            self.fallbackNote = fallbackNote
            // 지난번에 떠 있던 노트 창을 되살린다. 되살린 것이 없으면 하나를 띄운다.
            if notePanels.restoreOpenNotes().isEmpty { try fallbackNote.showFallbackNote() }
            #if DEBUG
            try startDebugging(router: router, notePanels: notePanels)
            #endif
            activationFocus.launchFinished(at: ProcessInfo.processInfo.systemUptime)
        } catch {
            presentLaunchFailure(error)
        }
    }

    /// 다른 프로그램이 제자리에서 고친 노트 파일은 폴더 감시가 잡지 못한다. 앱이 앞으로 올 때 다시 훑는다.
    /// 노트 창은 눌러도 앱을 앞으로 가져오지 않으므로, 노트 창이 키 창이 될 때는 `NotePanelCoordinator`가 훑는다.
    ///
    /// 사용자가 앱을 앞으로 가져온 것이면(⌘Tab, Dock) 맨 앞 노트가 키 창이 된다. 노트 창은 저절로 키 창이 되지
    /// 않으므로 여기서 시키지 않으면 앱이 앞에 있어도 키를 받을 창이 없다. 켜면서 오는 활성화는 뺀다(D-025).
    func applicationDidBecomeActive(_ notification: Notification) {
        do {
            try environment?.notes.refresh()
        } catch {
            AppLog.warning("노트 폴더를 다시 읽지 못했습니다: \(error)")
        }
        // 알림 창이나 캡처 바, 노트 찾기가 키 입력을 받는 중이면 노트가 그것을 가져가지 않는다.
        let isKeyHeldElsewhere = NSApplication.shared.modalWindow != nil || quickPanels?.isAnyVisible == true
        if activationFocus.shouldFocusNote(
            activatedAt: ProcessInfo.processInfo.systemUptime, isKeyHeldElsewhere: isKeyHeldElsewhere
        ) {
            notePanels?.focusFrontmostNote()
        }
    }

    /// 끝내기 전에 미뤄 둔 저장을 모두 쓴다. 못 쓴 노트가 있으면 이름을 보여 주고 끝낼지 묻는다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let notes = environment?.notes else { return .terminateNow }
        // 편집기가 아직 알리지 않은 글과 고치던 제목을 먼저 받는다.
        notePanels?.flushPendingEdits()
        // 한데 모아 쓰려고 미뤄 둔 창 상태를 쓴다. 쓰지 못해도 끝내기를 막지 않는다(노트의 글이 아니다).
        do {
            try environment?.windowStates.flush()
        } catch {
            AppLog.warning("끝내기 전에 창 상태를 저장하지 못했습니다: \(error)")
        }
        do {
            try notes.flushPendingSaves()
            return .terminateNow
        } catch {
            AppLog.warning("끝내기 전에 저장하지 못했습니다: \(error)")
            return UnsavedNotesAlert.confirmQuit(after: error) ? .terminateNow : .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock 아이콘을 눌렀을 때: 숨긴 노트를 되돌리고, 떠 있는 노트가 없으면 하나를 띄우고, 맨 앞 노트가
    /// 키 창이 된다. 띄우지 못하면 알림 창으로 까닭을 보여 준다(`FallbackNotePresenter`).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        fallbackNote?.handleReopen()
        return false
    }

    // MARK: - 메뉴 막대 아이콘과 Dock 메뉴

    /// 메뉴 막대 아이콘을 보이거나 감추고 설정에 적는다(설정 화면이 부른다). 감춰도 같은 항목이 Dock 메뉴와
    /// 앱 메뉴에 있고, 전역 단축키도 그대로다.
    func setMenuBarIconShown(_ shown: Bool) {
        do {
            try environment?.settings.update { $0.showsMenuBarIcon = shown }
        } catch {
            AppLog.warning("메뉴 막대 아이콘 설정을 저장하지 못했습니다: \(error)")
        }
        menuBarIcon?.apply(shown: shown)
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
        control.start()
        debugControl = control
    }
    #endif

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
