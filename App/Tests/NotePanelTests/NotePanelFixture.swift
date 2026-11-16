import AppKit
import Foundation
import Models
import Routing
import Store
import Theme
@testable import NotePanel

/// 임시 폴더의 저장소와 테마로 노트 창을 실제로 만들어 보는 시험용 조립.
@MainActor
final class NotePanelFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("note-panel-tests-\(UUID().uuidString)", isDirectory: true)
    let location: StoreLocation
    let theme: Theme
    let notes: FileNoteStore
    private(set) var routes: [Route] = []
    private(set) var logs: [String] = []

    init() throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        location = .isolated(notesDirectory: root)
        theme = try Theme.bundled()
        // 자동 저장은 시험이 직접 flush한다.
        notes = try FileNoteStore(location: location, autosaveDelay: .seconds(60), autosaveMaxWait: .seconds(120))
    }

    /// 앱을 다시 켠 것처럼 상태 파일을 새로 읽는 노트 창 묶음.
    func makeCoordinator() throws -> NotePanelCoordinator {
        NotePanelCoordinator(
            theme: theme, notes: notes, windowStates: try WindowStateStore(location: location),
            spaces: try SpaceStore(location: location),
            router: RouteDispatcher { [unowned self] in routes.append($0) },
            log: { [unowned self] in logs.append($0) }
        )
    }

    func windowState(for id: NoteID) throws -> NoteWindowState? {
        try WindowStateStore(location: location).state(for: id)
    }

    func noteFile(_ id: NoteID) -> URL {
        location.notesDirectory.appendingPathComponent("\(id.rawValue).md")
    }

    func trashFile(_ id: NoteID) -> URL {
        location.trashDirectory.appendingPathComponent("\(id.rawValue).md")
    }

    /// 다른 프로그램처럼 파일 끝에 덧붙인다.
    func appendOutside(_ text: String, to id: NoteID) throws {
        let handle = try FileHandle(forWritingTo: noteFile(id))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func cleanUp(_ coordinator: NotePanelCoordinator? = nil) {
        coordinator?.controllers.values.forEach { $0.discardWindow() }
        try? FileManager.default.removeItem(at: root)
    }
}
