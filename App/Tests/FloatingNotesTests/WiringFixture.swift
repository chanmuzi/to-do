import AppKit
@_spi(Verification) import Browse
@_spi(Verification) import Capture
import Foundation
import Models
@_spi(Verification) @testable import NotePanel
import Routing
import Store
import Theme
@testable import FloatingNotes

/// 임시 폴더의 저장소로 App의 조립 전체(실제 `AppRouter`, 노트 창, Markdown 편집기, 캡처 바, 노트 찾기,
/// 동작 전달)를 만들어 보는 시험용 묶음. `AppDelegate`가 잇는 것과 같은 차례로 잇는다.
///
/// 시험은 실제 키 창을 만들지 않는다(사용자가 다른 앱에 치던 글자를 가져온다). 노트 창이 키 창이 되도록
/// "시켰는지"(`keyRequests`)를 보고, 어느 노트가 키 창인지는 `pretendKey(_:)`로 정한다. 캡처 바와 노트 찾기는
/// 화면에 올리되 투명하게 두고 키 창으로 만들지 않는다.
final class WiringFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("wiring-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let windowStates: WindowStateStore
    let spaces: SpaceStore
    let router = AppRouter()
    let editors: NoteEditorFactory
    let notePanels: NotePanelCoordinator
    let quickPanels: QuickPanels
    let commands: AppCommandDispatcher
    /// 캡처 바와 노트 찾기가 듣는 알림 센터. 시험이 "키 창에서 물러났다"를 여기로 보낸다(`resignKey(_:)`).
    let panelNotifications = NotificationCenter()
    /// 앱이 앞에 있는 것으로 칠지.
    var isAppActive = false
    /// 지금 처리 중인 것으로 칠 이벤트의 종류(`beginPress()`, `releasePress()`, `endPress()`가 바꾼다).
    var currentEventType: NSEvent.EventType?
    /// 실패 알림이 떠 있는 동안 할 일(알림 창이 키 창을 가져가는 것을 흉내 낸다).
    var whileFailureIsShown: (() -> Void)?

    /// - Parameter makeBodyEditor: 주지 않으면 앱처럼 Markdown 편집기를 끼운다.
    init(makeBodyEditor: NoteBodyEditorFactory? = nil) throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        location = .isolated(notesDirectory: root)
        theme = try Theme.bundled()
        // 자동 저장은 시험이 직접 flush한다.
        notes = try FileNoteStore(location: location, autosaveDelay: .seconds(60), autosaveMaxWait: .seconds(120))
        windowStates = try WindowStateStore(location: location)
        spaces = try SpaceStore(location: location)
        let logBox = LogBox()
        editors = NoteEditorFactory(windowStates: windowStates, log: { logBox.lines.append($0) })
        notePanels = NotePanelCoordinator(
            theme: theme, notes: notes, windowStates: windowStates, spaces: spaces, router: router,
            makeBodyEditor: makeBodyEditor ?? editors.makeEditor, log: { logBox.lines.append($0) }
        )
        notePanels.allowsKeyWindows = false
        router.notePanels = notePanels
        quickPanels = QuickPanels(
            theme: theme, notes: notes, spaces: spaces, windowStates: windowStates, router: router,
            notePanels: notePanels, log: { logBox.lines.append($0) }
        )
        quickPanels.capture.takesKeyOnShow = false
        quickPanels.capture.isShownOpaque = false
        quickPanels.browse.takesKeyOnShow = false
        quickPanels.browse.isShownOpaque = false
        quickPanels.capture.notificationCenter = panelNotifications
        quickPanels.browse.notificationCenter = panelNotifications
        router.quickPanels = quickPanels
        commands = AppCommandDispatcher(router: router, notePanels: notePanels)
        commands.closeQuickPanel = { [unowned quickPanels] in quickPanels.closeVisiblePanel() }
        self.logBox = logBox
        let failureBox = FailureBox()
        self.failureBox = failureBox
        router.presentFailure = { [unowned self] title, _ in
            failureBox.titles.append(title)
            whileFailureIsShown?()
        }
        quickPanels.presentFailure = { [unowned self] title, _ in
            failureBox.titles.append(title)
            whileFailureIsShown?()
        }
        quickPanels.isAppActive = { [unowned self] in isAppActive }
        quickPanels.currentEventType = { [unowned self] in currentEventType }
    }

    /// 이 앱의 창에 마우스 버튼이 눌렸다(`PointerPressMonitor`가 알리는 것과 같은 차례).
    func beginPress() {
        currentEventType = .leftMouseDown
        quickPanels.pointerPressBegan()
    }

    /// 버튼을 뗐다. 이제 뗀 이벤트를 처리하는 중이다(버튼의 동작이 이때 돈다).
    func releasePress() {
        currentEventType = .leftMouseUp
    }

    /// 뗀 이벤트의 처리가 끝났다.
    func endPress() {
        quickPanels.pointerPressEnded()
        currentEventType = nil
    }

    /// 그 화면이 키 창에서 물러났다고 알린다(바깥을 누름, 다른 창이 키 창이 됨). 시험은 실제 키 창을 만들지
    /// 않으므로 AppKit이 보내는 알림을 직접 보낸다.
    func resignKey(_ window: NSWindow?) {
        panelNotifications.post(name: NSWindow.didResignKeyNotification, object: window)
    }

    private let logBox: LogBox
    private let failureBox: FailureBox

    /// 알림 창 대신 받아 둔 실패(제목).
    var shownFailures: [String] { failureBox.titles }
    var logLines: [String] { logBox.lines }
    var capture: CaptureCoordinator { quickPanels.capture }
    var browse: BrowseCoordinator { quickPanels.browse }

    /// 노트를 만들어 창을 띄운다(키 창으로 만들라고 시키지 않는다).
    func open(_ title: String, body: String = "") throws -> NoteID {
        let note = try notes.create(NoteDraft(title: title, body: body))
        try notePanels.open(note.id, focus: false)
        return note.id
    }

    /// 그 노트의 창이 키 창인 것처럼 본다. `nil`이면 키 창인 노트가 없다.
    func pretendKey(_ id: NoteID?) {
        let panel = id.flatMap { notePanels.controllers[$0]?.panel }
        notePanels.isKeyPanel = { panel != nil && $0 === panel }
    }

    /// 그 노트의 창에게 키 창이 되라고 시킨 횟수.
    func keyRequests(_ id: NoteID) -> Int {
        notePanels.controllers[id]?.panel.keyRequestCount ?? -1
    }

    func fileText(_ id: NoteID) throws -> String {
        try String(
            contentsOf: location.notesDirectory.appendingPathComponent("\(id.rawValue).md"), encoding: .utf8
        )
    }

    /// 노트 찾기의 줄에서 노트 줄의 제목만 뽑는다. 떠 있는 노트(핀이 보이는 줄)에는 `(핀)`을 붙인다.
    var browseTitles: [String] {
        browse.rowDescriptions.compactMap { line in
            let parts = line.dropFirst().components(separatedBy: " | ")
            guard parts.count == 5, parts[0].hasPrefix("note ") else { return nil }
            return parts[1] + (parts[4] == "pin" ? "(핀)" : "")
        }
    }

    /// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다(노트 찾기는 다음 차례에 목록을 다시 읽는다).
    func wait(upTo seconds: Double = 3, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func cleanUp() {
        capture.window?.orderOut(nil)
        browse.window?.orderOut(nil)
        notePanels.openNoteIDs.forEach { notePanels.window(for: $0)?.close() }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    private final class LogBox {
        var lines: [String] = []
    }

    private final class FailureBox {
        var titles: [String] = []
    }
}
