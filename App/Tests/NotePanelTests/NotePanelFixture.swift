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
    /// - Parameter makeBodyEditor: 주지 않으면 기본 편집기를 쓴다.
    /// 시험 중에 뜨는 창이 키 창이 되어 사용자가 다른 앱에 치던 글자를 받지 않게 한다.
    func makeCoordinator(makeBodyEditor: NoteBodyEditorFactory? = nil) throws -> NotePanelCoordinator {
        let coordinator = NotePanelCoordinator(
            theme: theme, notes: notes, windowStates: try WindowStateStore(location: location),
            spaces: try SpaceStore(location: location),
            router: RouteDispatcher { [unowned self] in routes.append($0) },
            makeBodyEditor: makeBodyEditor ?? { PlainTextBodyEditor(theme: $0.theme) },
            log: { [unowned self] in logs.append($0) }
        )
        coordinator.allowsKeyWindows = false
        return coordinator
    }

    /// "동작 줄이기"가 켜져 있으면 전환이 바로 끝난다.
    var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다(움직임이 끝나기를 기다릴 때).
    func wait(upTo seconds: Double = 3, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
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

    /// 다른 프로그램처럼 파일 전체를 바꿔 쓴다(제자리에서).
    func rewriteOutside(_ id: NoteID, _ change: (String) -> String) throws {
        let text = try String(contentsOf: noteFile(id), encoding: .utf8)
        let handle = try FileHandle(forWritingTo: noteFile(id))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(change(text).utf8))
        try handle.close()
    }

    func cleanUp(_ coordinator: NotePanelCoordinator? = nil) {
        coordinator?.controllers.values.forEach { $0.discardWindow() }
        try? FileManager.default.removeItem(at: root)
    }
}
