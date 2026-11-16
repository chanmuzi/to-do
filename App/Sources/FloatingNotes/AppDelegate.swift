import AppKit
import Store
import Theme

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var environment: AppEnvironment?
    private var router: AppRouter?
    private var placeholderWindow: PlaceholderWindowController?

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
            router = AppRouter()
            application.mainMenu = MainMenu.make(appName: ProcessInfo.processInfo.processName)
            try showInitialWindows(environment)
            application.activate()
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

    /// 앱을 켰을 때 띄울 창. 2단계에서 열려 있던 노트 창을 되살리는 코드로 바꾼다.
    private func showInitialWindows(_ environment: AppEnvironment) throws {
        let listing = try environment.notes.list()
        for failure in listing.failures {
            AppLog.warning("노트 파일을 읽지 못해 건너뜁니다: \(failure.error)")
        }
        let controller = PlaceholderWindowController(environment: environment, noteCount: listing.notes.count)
        controller.showWindow(nil)
        placeholderWindow = controller
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
