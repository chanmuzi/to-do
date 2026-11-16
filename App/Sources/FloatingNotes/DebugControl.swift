#if DEBUG
import AppKit
import Models
import NotePanel
import Routing

/// 확인용 명령을 받는 곳. 디버그 빌드에서 `--debug-control <출력 폴더>`로 켰을 때만 듣는다.
/// 마우스와 키보드를 건드리지 않고 실행 중인 앱의 상태를 바꾸고 읽기 위한 것이다. 릴리스 빌드에는 없다.
///
/// 다른 프로세스가 분산 알림 `local.floating-notes.debug`의 `object`에 `<표> <명령>` 한 줄을 실어 보낸다.
/// 표는 켤 때마다 새로 만들어 `<출력 폴더>/control-token`에 적는다(`DebugControlSession`).
/// 표가 없거나 틀린 명령은 버린다. `scripts/debug-send.sh <출력 폴더> <명령...>`이 표를 읽어 보낸다.
///
/// - `open|close|trash <id>`, `new [<옆에 둘 노트 id>]`, `toggle-hidden`: 라우터나 노트 창으로 넘긴다.
/// - `focus <id>`: 앱을 앞으로 가져와 그 노트 본문에 커서를 둔다. `unfocus`: 그 전에 앞에 있던 앱으로 돌려준다.
/// - `hover <id> on|off|auto`, `pin <id> on|off`, `color <id> <팔레트 키|none>`
/// - `menu <id> <파일 이름>`: 더 보기 메뉴를 띄워 그 모습을 PNG로 쓰고 닫는다.
/// - `snapshot <id> <파일 이름>`: 그 노트 창의 내용을 앱 안에서 그려 PNG로 쓴다. 화면을 찍지 않으므로
///   화면 기록 권한이 필요 없지만, 뒤 배경 흐림과 창 그림자는 담기지 않는다.
/// - `dump <파일 이름>`: 떠 있는 노트 창의 틀, 창 단계, 핀, 호버 상태를 JSON으로 쓴다.
/// - `quit`
///
/// 파일 이름은 출력 폴더 바로 아래의 이름이어야 한다. 경로를 주면 쓰지 않는다.
final class DebugControl {
    static let notificationName = Notification.Name("local.floating-notes.debug")

    private let session: DebugControlSession
    private let router: any Routing
    private let notePanels: NotePanelCoordinator
    private var observer: (any NSObjectProtocol)?
    private var previousApplication: NSRunningApplication?

    init(session: DebugControlSession, router: any Routing, notePanels: NotePanelCoordinator) {
        self.session = session
        self.router = router
        self.notePanels = notePanels
    }

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] notification in
            guard let payload = notification.object as? String else { return }
            MainActor.assumeIsolated { self?.receive(payload) }
        }
    }

    private func receive(_ payload: String) {
        guard let command = session.command(from: payload) else {
            AppLog.warning("표가 맞지 않는 확인용 명령을 버렸습니다")
            return
        }
        run(command)
    }

    private func run(_ command: String) {
        let words = command.split(separator: " ", maxSplits: 2).map(String.init)
        let id = words.count > 1 ? NoteID(rawValue: words[1]) : nil
        let argument = words.count > 2 ? words[2] : nil
        switch (words.first, id, argument) {
        case ("open", let id?, _): router.route(.openNote(id))
        case ("close", let id?, _): router.route(.closeNoteWindow(id))
        case ("new", _, _): router.route(.newNote(NewNoteRequest(nextTo: id)))
        case ("toggle-hidden", _, _): router.route(.toggleAllNotesHidden)
        case ("trash", let id?, _): notePanels.moveToTrash(id)
        case ("focus", let id?, _):
            previousApplication = NSWorkspace.shared.frontmostApplication
            NSApplication.shared.activate()
            notePanels.focusBody(of: id)
        case ("unfocus", _, _):
            previousApplication?.activate()
            previousApplication = nil
        case ("hover", let id?, let state?):
            notePanels.setHoverOverride(state == "auto" ? nil : state == "on", for: id)
        case ("pin", let id?, let state?): notePanels.setPinned(state == "on", for: id)
        case ("color", let id?, let key?):
            notePanels.setColor(key == "none" ? nil : PaletteID(rawValue: key), for: id)
        case ("menu", let id?, let name?):
            guard let url = output(named: name) else { return }
            showMoreMenu(for: id, snapshotURL: url)
        case ("snapshot", let id?, let name?):
            guard let url = output(named: name) else { return }
            let number = notePanels.snapshot(of: id)?.windowNumber
            write(NSApplication.shared.windows.first { $0.windowNumber == number }, to: url)
        case ("dump", _, _):
            guard let url = output(named: String(command.dropFirst("dump ".count))) else { return }
            dump(to: url)
        case ("quit", _, _): NSApplication.shared.terminate(nil)
        default: AppLog.warning("모르는 확인용 명령입니다: \(command)")
        }
    }

    private func output(named name: String) -> URL? {
        guard let url = session.outputURL(named: name) else {
            AppLog.warning("확인용 출력은 출력 폴더 바로 아래의 파일 이름으로만 받습니다: \(name)")
            return nil
        }
        return url
    }

    /// 메뉴는 닫힐 때까지 돌아오지 않는다. 메뉴가 도는 동안에도 불리는 타이머로 모습을 쓰고 esc를 넣어 닫는다.
    private func showMoreMenu(for id: NoteID, snapshotURL: URL) {
        let known = Set(NSApplication.shared.windows.map(\.windowNumber))
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write(NSApplication.shared.windows.first { !known.contains($0.windowNumber) }, to: snapshotURL)
                guard let escape = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
                ) else { return }
                NSApplication.shared.postEvent(escape, atStart: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        notePanels.popUpMoreMenu(for: id)
    }

    /// 창의 내용 뷰를 앱 안에서 그려 PNG로 쓴다.
    private func write(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            AppLog.warning("그릴 창을 찾지 못했습니다: \(url.lastPathComponent)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                AppLog.warning("PNG로 바꾸지 못했습니다: \(url.lastPathComponent)")
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.warning("확인용 그림을 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }

    private func dump(to url: URL) {
        let windows = notePanels.openNoteIDs.compactMap(notePanels.snapshot(of:)).map { window in
            [
                "id": window.noteID.rawValue,
                "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
                "pinned": window.isPinned,
                "level": window.level,
                "visible": window.isVisible,
                "key": window.isKey,
                "hovered": window.isHovered,
                "windowNumber": window.windowNumber,
                "problem": window.problem ?? "",
            ] as [String: Any]
        }
        let document: [String: Any] = [
            "hidden": notePanels.areNotesHidden,
            "appActive": NSApplication.shared.isActive,
            "keyWindowNumber": NSApplication.shared.keyWindow?.windowNumber ?? 0,
            "firstResponder": NSApplication.shared.keyWindow?.firstResponder.map { "\(type(of: $0))" } ?? "",
            "windows": windows,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.warning("확인용 상태를 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }
}
#endif
