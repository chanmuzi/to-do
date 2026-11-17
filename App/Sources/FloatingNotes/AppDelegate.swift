import AppKit
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
    private var library: LibraryCoordinator?
    private var quickPanels: QuickPanels?
    private var editors: NoteEditorFactory?
    private var commands: AppCommandDispatcher?
    private var menuBarIcon: MenuBarIconSwitch<StatusItemController>?
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
            router.activateApp = { if !application.isActive { application.activate() } }
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
            // 빠른 캡처와 노트 찾기. 노트 창과 같은 창 상태를 넘겨 "떠 있는 노트"와 핀이 보이게 한다.
            let quickPanels = QuickPanels(
                theme: environment.theme, notes: environment.notes, spaces: environment.spaces,
                windowStates: environment.windowStates, router: router, notePanels: notePanels,
                log: AppLog.warning
            )
            #if DEBUG
            if options.debugIsPassive { quickPanels.refuseKeyWindowsForVerification() }
            #endif
            let library = LibraryCoordinator(theme: environment.theme, notes: environment.notes,
                spaces: environment.spaces, windows: environment.windowStates,
                preferences: try LibraryPreferencesStore(location: environment.location), router: router)
            library.beforeMove = { [weak notePanels] in notePanels?.flushPendingEdits() }
            #if DEBUG
            library.allowsKeyWindows = !options.debugIsPassive
            #endif
            router.library = library
            self.library = library
            router.quickPanels = quickPanels
            self.router = router
            self.notePanels = notePanels
            self.quickPanels = quickPanels
            self.editors = editors

            let commands = AppCommandDispatcher(router: router, notePanels: notePanels)
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

    /// 다른 프로그램이 제자리에서 고친 노트 파일은 폴더 감시가 잡지 못한다. 앱이 앞으로 올 때 다시 훑는다.
    ///
    /// 사용자가 앱을 앞으로 가져왔는데(⌘Tab, Dock) 키 창인 노트가 없으면 맨 앞 노트가 키 창이 되어 키보드만으로
    /// 이어 쓴다. 노트를 눌러 앞으로 온 것이면 그 누름이 그 노트를 키 창으로 만든다. 누름은 이 알림 뒤에 처리되므로
    /// 한 차례 미뤄 본다: 그때 키 창인 노트가 있으면 아무것도 하지 않는다. 켜면서 오는 활성화는 뺀다(D-025).
    func applicationDidBecomeActive(_ notification: Notification) {
        do {
            try environment?.notes.refresh()
        } catch {
            AppLog.warning("노트 폴더를 다시 읽지 못했습니다: \(error)")
        }
        // 알림 창이나 캡처 바, 노트 찾기가 키 입력을 받는 중이면 노트가 그것을 가져가지 않는다.
        let isKeyHeldElsewhere = NSApplication.shared.modalWindow != nil || quickPanels?.isAnyVisible == true
        guard activationFocus.shouldFocusNote(
            activatedAt: ProcessInfo.processInfo.systemUptime, isKeyHeldElsewhere: isKeyHeldElsewhere
        ) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApplication.shared.isActive, NSApplication.shared.keyWindow == nil,
                  quickPanels?.isAnyVisible != true
            else { return }
            notePanels?.focusFrontmostNote()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock 아이콘을 눌렀을 때: 숨긴 노트를 되돌리고, 떠 있는 노트가 없으면 하나를 띄우고, 맨 앞 노트가
    /// 키 창이 된다. 띄우지 못하면 알림 창으로 까닭을 보여 준다(`FallbackNotePresenter`).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if notePanels?.areNotesHidden == true { notePanels?.toggleAllHidden() }
        if notePanels?.openNoteIDs.isEmpty != false { router?.route(.openLibrary) }
        else { notePanels?.focusFrontmostNote() }
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

    /// 메뉴에 쓰는 지역화된 앱 이름(`InfoPlist.strings`의 "Float").
    /// object(forInfoDictionaryKey:)는 지역화 값을 우선한다. SwiftPM 실행·테스트에는 Float를 쓴다.
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
        control.library = library
        control.reopen = { [weak self] in _ = self?.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false) }
        control.toastWindow = { [unowned self] in toasts?.presenter.window }
        control.toastAction = { [unowned self] in toasts?.presenter.performAction() }
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
