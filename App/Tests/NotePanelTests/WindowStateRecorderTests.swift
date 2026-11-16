import CoreGraphics
import Foundation
import Models
import Store
import Testing
@testable import NotePanel

@Suite @MainActor struct WindowStateRecorderTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("note-panel-tests-\(UUID().uuidString)", isDirectory: true)
    private var location: StoreLocation { .isolated(notesDirectory: root) }
    private let id = NoteID(rawValue: "a")
    private let frame = CGRect(x: 100, y: 200, width: 340, height: 180)

    private func recorder() throws -> WindowStateRecorder {
        WindowStateRecorder(store: try WindowStateStore(location: location), log: { _ in })
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aNoteNeverShownStartsPinnedAndClosed() throws {
        defer { cleanUp() }
        let state = try recorder().state(for: id)
        #expect(state == NoteWindowState(frame: nil, isPinned: true, isOpen: false))
    }

    @Test func openingRecordsFrameAndPinAndSurvivesARelaunch() throws {
        defer { cleanUp() }
        try recorder().recordOpened(id, frame: frame, isPinned: true)

        let relaunched = try recorder()
        #expect(relaunched.openNoteIDs == [id])
        #expect(relaunched.state(for: id) == NoteWindowState(frame: WindowFrame(frame), isPinned: true, isOpen: true))
    }

    @Test func movingAndPinningChangeOnlyTheirOwnField() throws {
        defer { cleanUp() }
        let recorder = try recorder()
        recorder.recordOpened(id, frame: frame, isPinned: true)
        let moved = frame.offsetBy(dx: 30, dy: -40)
        recorder.recordFrame(id, frame: moved)
        recorder.recordPinned(id, isPinned: false)

        #expect(recorder.state(for: id) == NoteWindowState(frame: WindowFrame(moved), isPinned: false, isOpen: true))
    }

    @Test func closingKeepsFrameAndPinButIsNotRestored() throws {
        defer { cleanUp() }
        let recorder = try recorder()
        recorder.recordOpened(id, frame: frame, isPinned: false)
        recorder.recordClosed(id)

        let relaunched = try self.recorder()
        #expect(relaunched.openNoteIDs.isEmpty)
        #expect(relaunched.state(for: id) == NoteWindowState(frame: WindowFrame(frame), isPinned: false, isOpen: false))
    }

    @Test func forgettingRemovesTheEntry() throws {
        defer { cleanUp() }
        let recorder = try recorder()
        recorder.recordOpened(id, frame: frame, isPinned: true)
        recorder.forget(id)

        #expect(try self.recorder().state(for: id) == NoteWindowState())
        #expect(try WindowStateStore(location: location).all.isEmpty)
    }

    @Test func openNotesComeBackInAStableOrder() throws {
        defer { cleanUp() }
        let recorder = try recorder()
        for name in ["c", "a", "b"] {
            recorder.recordOpened(NoteID(rawValue: name), frame: frame, isPinned: true)
        }
        recorder.recordClosed(NoteID(rawValue: "b"))
        #expect(recorder.openNoteIDs.map(\.rawValue) == ["a", "c"])
    }
}
