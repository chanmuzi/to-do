import AppKit
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
            router = AppRouter()
            application.mainMenu = MainMenu.make(appName: ProcessInfo.processInfo.processName)
            try showInitialWindows(environment)
            application.activate()
        } catch {
            presentLaunchFailure(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        do {
            try environment?.notes.flushPendingSaves()
        } catch {
            FileHandle.standardError.write(Data("끝내기 전에 저장하지 못했습니다: \(error)\n".utf8))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 앱을 켰을 때 띄울 창. 2단계에서 열려 있던 노트 창을 되살리는 코드로 바꾼다.
    private func showInitialWindows(_ environment: AppEnvironment) throws {
        let controller = try PlaceholderWindowController(environment: environment)
        controller.showWindow(nil)
        placeholderWindow = controller
    }

    private func presentLaunchFailure(_ error: Error) {
        FileHandle.standardError.write(Data("앱을 시작하지 못했습니다: \(error)\n".utf8))
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "앱을 시작하지 못했습니다"
        alert.informativeText = "\(error)"
        alert.runModal()
        exit(1)
    }
}
