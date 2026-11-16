import AppKit
import Foundation
import Models
import NotePanel
import Routing
import Store
import Theme
@testable import FloatingNotes

/// 임시 폴더의 저장소로 App의 조립(노트 창 + Markdown 편집기 + 동작 전달)을 실제로 만들어 보는 시험용 묶음.
final class AppFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("app-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    let windowStates: WindowStateStore
    let editors: NoteEditorFactory
    let notePanels: NotePanelCoordinator
    let commands: AppCommandDispatcher

    /// - Parameter forwardsNoteRoutes: 노트 창 요청(열기, 새 노트, 닫기, 숨기기)을 실제 노트 창으로 넘긴다.
    init(forwardsNoteRoutes: Bool = true) throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        location = .isolated(notesDirectory: root)
        theme = try Theme.bundled()
        // 자동 저장은 시험이 직접 flush한다.
        notes = try FileNoteStore(location: location, autosaveDelay: .seconds(60), autosaveMaxWait: .seconds(120))
        windowStates = try WindowStateStore(location: location)
        let logBox = LogBox()
        editors = NoteEditorFactory(windowStates: windowStates, log: { logBox.lines.append($0) })
        let routeBox = RouteBox()
        let router = RouteDispatcher { routeBox.append($0) }
        notePanels = NotePanelCoordinator(
            theme: theme, notes: notes, windowStates: windowStates, spaces: try SpaceStore(location: location),
            router: router, makeBodyEditor: editors.makeEditor, log: { logBox.lines.append($0) }
        )
        // 시험 중에 뜨는 창이 키 창이 되어 사용자가 다른 앱에 치던 글자를 받지 않게 한다.
        notePanels.allowsKeyWindows = false
        commands = AppCommandDispatcher(router: router, notePanels: notePanels)
        self.routeBox = routeBox
        self.logBox = logBox
        if forwardsNoteRoutes {
            routeBox.forward = { [unowned notePanels] route in
                switch route {
                case .openNote(let id): try? notePanels.open(id, focus: false)
                case .newNote(let request): _ = try? notePanels.createNote(request)
                case .closeNoteWindow(let id): notePanels.closeWindow(id)
                case .toggleAllNotesHidden: notePanels.toggleAllHidden()
                default: break
                }
            }
        }
    }

    private let routeBox: RouteBox
    private let logBox: LogBox

    var receivedRoutes: [Route] { routeBox.received }
    var logLines: [String] { logBox.lines }

    /// 노트를 만들어 창을 띄우고 그 창의 편집기 어댑터를 돌려준다.
    func open(_ draft: NoteDraft) throws -> (NoteID, MarkdownBodyEditor) {
        let note = try notes.create(draft)
        try notePanels.open(note.id, focus: false)
        guard let editor = editors.editor(for: note.id) else { throw MissingEditor() }
        return (note.id, editor)
    }

    func noteFile(_ id: NoteID) -> URL {
        location.notesDirectory.appendingPathComponent("\(id.rawValue).md")
    }

    func fileText(_ id: NoteID) throws -> String {
        try String(contentsOf: noteFile(id), encoding: .utf8)
    }

    /// 다른 프로그램처럼 파일 전체를 바꿔 쓴다(제자리에서).
    func rewriteOutside(_ id: NoteID, _ change: (String) -> String) throws {
        let text = try fileText(id)
        let handle = try FileHandle(forWritingTo: noteFile(id))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(change(text).utf8))
        try handle.close()
    }

    /// 앱을 다시 켠 것처럼 상태 파일을 새로 읽는다.
    func storedFolds(for id: NoteID) throws -> [Int]? {
        try WindowStateStore(location: location).state(for: id)?.foldedLines
    }

    func cleanUp() {
        notePanels.openNoteIDs.forEach { notePanels.window(for: $0)?.close() }
        try? FileManager.default.removeItem(at: root)
    }

    struct MissingEditor: Error {}

    private final class RouteBox {
        var received: [Route] = []
        var forward: ((Route) -> Void)?
        func append(_ route: Route) {
            received.append(route)
            forward?(route)
        }
    }

    private final class LogBox {
        var lines: [String] = []
    }
}
