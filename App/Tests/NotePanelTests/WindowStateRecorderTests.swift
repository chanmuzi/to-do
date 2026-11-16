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

    /// 앞으로 온 차례를 적어 두고, 다시 켤 때는 뒤에 있던 것부터 돌려준다(마지막이 맨 앞).
    @Test func openNotesComeBackInBackToFrontOrder() throws {
        defer { cleanUp() }
        let recorder = try recorder()
        let ids = ["a", "b", "c"].map(NoteID.init(rawValue:))
        for id in ids {
            recorder.recordOpened(id, frame: frame, isPinned: true)
            recorder.recordFronted(id)
        }
        #expect(recorder.openNoteIDs == ids)

        recorder.recordFronted(ids[0])
        #expect(recorder.openNoteIDs == [ids[1], ids[2], ids[0]])
        // 이미 맨 앞이면 차례가 바뀌지 않고, 틀이나 핀을 적어도 차례는 남는다.
        let front = recorder.state(for: ids[0]).stackOrder
        recorder.recordFronted(ids[0])
        recorder.recordFrame(ids[0], frame: frame.offsetBy(dx: 10, dy: 0))
        recorder.recordPinned(ids[0], isPinned: false)
        #expect(recorder.state(for: ids[0]).stackOrder == front)
        recorder.recordClosed(ids[2])

        let relaunched = try self.recorder()
        #expect(relaunched.openNoteIDs == [ids[1], ids[0]])
        #expect(relaunched.backToFront([ids[0], ids[1]]) == [ids[1], ids[0]])
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
