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
    private var debugControl: DebugControl?

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
            // 본문 편집기는 주지 않아 NotePanel의 기본 편집기를 쓴다. Editor 모듈을 끼울 때 makeBodyEditor를 넘긴다.
            let notePanels = NotePanelCoordinator(
                theme: environment.theme, notes: environment.notes, windowStates: environment.windowStates,
                spaces: environment.spaces, router: router, log: AppLog.warning
            )
            router.notePanels = notePanels
            self.router = router
            self.notePanels = notePanels

            application.mainMenu = MainMenu.make(appName: ProcessInfo.processInfo.processName, target: self)
            try showInitialWindows(environment, notePanels)
            startDebugging(router: router, notePanels: notePanels)
        } catch {
            presentLaunchFailure(error)
        }
    }

    /// 다른 프로그램이 제자리에서 고친 노트 파일은 폴더 감시가 잡지 못한다. 앱이 앞으로 올 때 다시 훑는다.
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

    // MARK: - 메뉴

    @objc func newNote(_ sender: Any?) {
        router?.route(.newNote(NewNoteRequest(nextTo: notePanels?.keyNoteID)))
    }

    @objc func closeNoteWindow(_ sender: Any?) {
        guard let id = notePanels?.keyNoteID else { return }
        router?.route(.closeNoteWindow(id))
    }

    // MARK: - 켤 때

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

    private func startDebugging(router: AppRouter, notePanels: NotePanelCoordinator) {
        options.debugHover.forEach { notePanels.setHoverOverride(true, for: $0) }
        guard options.debugControl else { return }
        let control = DebugControl(router: router, notePanels: notePanels)
        control.start()
        debugControl = control
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
