import AppKit
import Foundation
import Models
import NotePanel
import Routing
import Store
import Testing
import Theme
@testable import FloatingNotes

@Suite struct AppRouterTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("app-router-tests-\(UUID().uuidString)", isDirectory: true)

    private func makeRouter() throws -> (AppRouter, NotePanelCoordinator, FileNoteStore) {
        _ = NSApplication.shared
        let location = StoreLocation.isolated(notesDirectory: root)
        let notes = try FileNoteStore(location: location)
        let router = AppRouter()
        let coordinator = NotePanelCoordinator(
            theme: try Theme.bundled(), notes: notes, windowStates: try WindowStateStore(location: location),
            spaces: try SpaceStore(location: location), router: router, log: { _ in }
        )
        router.notePanels = coordinator
        // 시험 중에 뜨는 창이 키 창이 되어 사용자가 다른 앱에 치던 글자를 받지 않게 한다.
        coordinator.allowsKeyWindows = false
        return (router, coordinator, notes)
    }

    /// 새 노트를 만들지 못하면(디스크가 가득 참, 폴더에 쓸 수 없음) 기록만 하지 않고 사용자에게 알린다.
    @Test func failedNewNoteIsShownToTheUser() throws {
        let (router, coordinator, _) = try makeRouter()
        var shown: [(title: String, error: Error)] = []
        router.presentFailure = { shown.append((title: $0, error: $1)) }
        // 노트 폴더에 쓸 수 없게 한다.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }

        router.route(.newNote(NewNoteRequest()))

        #expect(shown.count == 1)
        #expect(shown.first?.title == "새 노트를 만들지 못했습니다")
        #expect(shown.first?.error is StoreError)
        #expect(coordinator.openNoteIDs.isEmpty)
    }

    @Test func failedOpenIsShownAndSuccessfulRoutesAreNot() throws {
        let (router, coordinator, notes) = try makeRouter()
        defer { try? FileManager.default.removeItem(at: root) }
        var shown: [String] = []
        router.presentFailure = { title, _ in shown.append(title) }

        router.route(.openNote(NoteID(rawValue: "missing")))
        #expect(shown == ["노트를 열지 못했습니다"])

        let note = try notes.create(NoteDraft(title: "있는 노트"))
        router.route(.openNote(note.id))
        router.route(.closeNoteWindow(note.id))
        router.route(.openSettings)
        #expect(shown.count == 1)
        #expect(coordinator.openNoteIDs.isEmpty)
        #expect(router.unhandled == [.openSettings])
    }
}
