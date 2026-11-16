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
    private var editors: NoteEditorFactory?
    private var commands: AppCommandDispatcher?
    private var statusItem: StatusItemController?
    private var menuBarIcon: NSImage?
    private var hotKeys: GlobalHotKeys?
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
            if options.debugIsPassive { notePanels.allowsKeyWindows = false }
            #endif
            router.notePanels = notePanels
            self.router = router
            self.notePanels = notePanels
            self.editors = editors

            let commands = AppCommandDispatcher(router: router, notePanels: notePanels)
            self.commands = commands
            let shortcuts = ShortcutTable.standard
            application.mainMenu = MainMenu.make(
                appName: ProcessInfo.processInfo.processName, table: shortcuts, dispatcher: commands
            )
            menuBarIcon = try MenuBarIcon.load()
            applyMenuBarIcon(
                shown: options.menuBarIconOverride ?? environment.settings.settings.showsMenuBarIcon
            )
            registerGlobalHotKeys(shortcuts, commands)
            try showInitialWindows(environment, notePanels)
            #if DEBUG
            try startDebugging(router: router, notePanels: notePanels)
            #endif
        } catch {
            presentLaunchFailure(error)
        }
    }

    /// 다른 프로그램이 제자리에서 고친 노트 파일은 폴더 감시가 잡지 못한다. 앱이 앞으로 올 때 다시 훑는다.
    /// 노트 창은 눌러도 앱을 앞으로 가져오지 않으므로, 노트 창이 키 창이 될 때는 `NotePanelCoordinator`가 훑는다.
    func applicationDidBecomeActive(_ notification: Notification) {
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

    /// Dock 아이콘을 눌렀을 때: 숨긴 노트를 되돌리고, 떠 있는 노트가 없으면 하나를 띄운다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let environment, let notePanels else { return false }
        if notePanels.areNotesHidden {
            notePanels.toggleAllHidden()
        } else if notePanels.openNoteIDs.isEmpty {
            do {
                try showFallbackNote(environment, notePanels)
            } catch {
                AppLog.warning("노트를 띄우지 못했습니다: \(error)")
            }
        }
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
        applyMenuBarIcon(shown: shown)
    }

    private func applyMenuBarIcon(shown: Bool) {
        guard shown else {
            statusItem = nil
            return
        }
        guard statusItem == nil, let environment, let notePanels, let commands, let menuBarIcon else { return }
        statusItem = StatusItemController(
            theme: environment.theme, icon: menuBarIcon,
            areNotesHidden: { [unowned notePanels] in notePanels.areNotesHidden },
            perform: { [unowned commands] in commands.performStatusMenu($0) }
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

    /// "어디서나" 쓰는 단축키를 등록한다. 다른 앱이 쓰는 키는 등록되지 않는다. 숨기지 않고 경고로 남긴다
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

    /// 지난번에 떠 있던 노트 창을 되살린다. 되살린 것이 없으면 하나를 띄운다.
    private func showInitialWindows(_ environment: AppEnvironment, _ notePanels: NotePanelCoordinator) throws {
        if notePanels.restoreOpenNotes().isEmpty {
            try showFallbackNote(environment, notePanels)
        }
    }

    /// 떠 있는 노트가 없을 때 띄울 것. 노트가 하나도 없으면 빈 노트를 새로 만든다
    /// (안내 문구 없이 커서만 있는 노트, spec 16과 규칙 3). 있으면 가장 최근에 고친 노트를 띄운다.
    private func showFallbackNote(_ environment: AppEnvironment, _ notePanels: NotePanelCoordinator) throws {
        let listing = try environment.notes.list()
        for failure in listing.failures {
            AppLog.warning("노트 파일을 읽지 못해 건너뜁니다: \(failure.error)")
        }
        if let recent = listing.notes.first {
            try notePanels.open(recent.id)
        } else {
            try notePanels.createNote()
        }
    }

    #if DEBUG
    private func startDebugging(router: AppRouter, notePanels: NotePanelCoordinator) throws {
        options.debugHover.forEach { notePanels.setHoverOverride(true, for: $0) }
        guard let directory = options.debugControlDirectory else { return }
        guard let editors, let commands else { return }
        let control = DebugControl(
            session: try DebugControlSession.start(in: directory), router: router, notePanels: notePanels,
            editors: editors, commands: commands, hotKeys: hotKeys, isPassive: options.debugIsPassive,
            statusItem: { [unowned self] in statusItem },
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
