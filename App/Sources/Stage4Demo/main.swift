import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Models
import Routing
import Store
import Theme

// 캡처 바와 노트 찾기만 띄워 본다. 화면 3, 9와 견주고 실제 입력 경로를 확인하는 데 쓴다.
// 창 번호를 표준 출력에 적으므로 그 창만 캡처할 수 있다: `screencapture -l <번호> out.png`
// 받은 요청(`Route`)과 기록도 표준 출력에 적는다. 노트 폴더는 `--notes-dir`로 준 곳만 쓴다.

func write(_ line: String) {
    FileHandle.standardOutput.write(Data("\(line)\n".utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(64)
}

/// 노트 찾기를 붙여 볼 가짜 노트 창. 노트 창 모듈을 쓰지 않는다(기능 모듈은 서로 기대지 않는다).
final class AnchorWindow: NSPanel {
    init(theme: Theme) {
        let size = NSSize(width: theme.component(.noteWidth), height: 200)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        backgroundColor = theme.nsColor(.surface)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        // 주 화면이 아닌 화면이 있으면 거기에, 없으면 주 화면의 오른쪽 위 구석에 둔다.
        let screen = NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameTopLeftPoint(NSPoint(x: visible.maxX - size.width - 40, y: visible.maxY - 40))
        }
    }

    override var canBecomeKey: Bool { true }
}

final class DemoDelegate: NSObject, NSApplicationDelegate {
    private let options: DemoOptions
    private var script: DemoScript?
    private var retained: [AnyObject] = []

    init(options: DemoOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registration = FontRegistrar.registerBundledFonts()
        registration.problems.forEach { FileHandle.standardError.write(Data("글꼴: \($0)\n".utf8)) }
        NSApp.appearance = options.appearance.nsAppearance

        do {
            try start()
        } catch {
            fail("시작하지 못했습니다: \(error)")
        }
    }

    private func start() throws {
        let theme = try Theme.bundled(appearance: options.appearance)
        let location = StoreLocation.isolated(notesDirectory: options.notesDirectory)
        try DemoSeed.seedIfEmpty(location: location, now: Date(), calendar: .current)
        let notes = try FileNoteStore(location: location)
        let spaces = try SpaceStore(location: location)
        let windowStates = try WindowStateStore(location: location)
        let router = RouteDispatcher { write("ROUTE \($0)") }

        let capture = CaptureCoordinator(theme: theme, notes: notes, spaces: spaces, router: router) { write("LOG \($0)") }
        let browse = BrowseCoordinator(
            theme: theme, notes: notes, spaces: spaces, router: router, windowStates: windowStates
        ) { write("LOG \($0)") }
        capture.takesKeyOnShow = options.activates
        browse.takesKeyOnShow = options.activates
        // 쓰는 사람의 화면을 덜 가리도록 주 화면이 아닌 화면이 있으면 거기에 띄운다.
        let side = NSScreen.screens.first { $0 != NSScreen.main }
        capture.preferredScreen = side
        browse.preferredScreen = side

        // 시안의 벽 색에 가까운 회색. 확인용 캡처의 배경일 뿐이라 토큰이 아니다.
        let wall = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.78, alpha: 1)
        }
        let script = DemoScript(
            capture: capture, browse: browse, anchor: AnchorWindow(theme: theme), wall: wall, output: write
        )
        self.script = script
        retained = [theme, notes, spaces, windowStates, router, capture, browse]

        Task { @MainActor [options] in
            await script.run(options.script)
            // 전환(`dur`)이 끝난 뒤에 찍는다.
            try? await Task.sleep(for: .milliseconds(400))
            script.dump()
            if let path = options.snapshotPath { script.snapshot(to: path) }
            if options.hold > 0 { try? await Task.sleep(for: .seconds(options.hold)) }
            do {
                try notes.flushPendingSaves()
            } catch {
                fail("저장하지 못한 노트가 있습니다: \(error)")
            }
            NSApp.terminate(nil)
        }
    }
}

let options: DemoOptions
do {
    options = try DemoOptions(arguments: CommandLine.arguments)
} catch {
    fail("\(error)")
}

let application = NSApplication.shared
let delegate = DemoDelegate(options: options)
application.delegate = delegate
// Dock에 나타나지 않고 다른 앱의 포커스를 빼앗지 않는다.
application.setActivationPolicy(.accessory)
application.run()
