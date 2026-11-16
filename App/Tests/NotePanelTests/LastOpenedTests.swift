import AppKit
import Foundation
import Models
import Store
import Testing
@_spi(Verification) @testable import NotePanel

/// 노트를 마지막으로 연 때(D-033): 사용자가 창을 띄우거나 키 창으로 만들 때 창 상태에 적는다.
/// 노트 찾기의 "최근에 연 노트"가 이 값으로 차례를 정한다.
@Suite @MainActor struct LastOpenedTests {
    private let fixture: NotePanelFixture

    init() throws {
        fixture = try NotePanelFixture()
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    @Test func openingANoteRecordsWhenItWasOpened() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var clock = date(0)
        coordinator.now = { clock }
        let first = try fixture.notes.create(NoteDraft(title: "하나")).id
        let second = try fixture.notes.create(NoteDraft(title: "둘")).id

        try coordinator.open(first, focus: false)
        clock = date(60)
        try coordinator.open(second, focus: false)
        #expect(try fixture.windowState(for: first)?.lastOpened == date(0))
        #expect(try fixture.windowState(for: second)?.lastOpened == date(60))

        // 떠 있는 노트를 다시 고르면(노트 찾기에서) 그때로 바뀐다. 이미 맨 앞이어도 적는다.
        clock = date(120)
        try coordinator.open(second, focus: false)
        #expect(try fixture.windowState(for: second)?.lastOpened == date(120))
        // 창을 닫아도 남는다.
        coordinator.closeWindow(first)
        #expect(try fixture.windowState(for: first)?.lastOpened == date(0))
        #expect(try fixture.windowState(for: first)?.isOpen == false)
    }

    /// 키 창이 되는 것도 연 것이다(누름, 다음 노트로, 앱을 앞으로 가져옴).
    @Test func becomingKeyRecordsTheTime() throws {
        let coordinator = try fixture.makeCoordinator()
        defer { fixture.cleanUp(coordinator) }
        var clock = date(0)
        coordinator.now = { clock }
        let id = try fixture.notes.create(NoteDraft(title: "하나")).id
        try coordinator.open(id, focus: false)
        let controller = try #require(coordinator.controllers[id])

        clock = date(300)
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: controller.panel))

        #expect(try fixture.windowState(for: id)?.lastOpened == date(300))
    }

    /// 켤 때 되살린 창은 사용자가 연 것이 아니다. 지난번에 적은 때가 그대로 남는다.
    @Test func restoringWindowsAtLaunchKeepsTheRecordedTimes() throws {
        let opened = date(0)
        let later = date(9_000)
        let first = try fixture.makeCoordinator()
        first.now = { opened }
        let id = try fixture.notes.create(NoteDraft(title: "하나")).id
        try first.open(id, focus: false)
        first.controllers.values.forEach { $0.discardWindow() }

        let relaunched = try fixture.makeCoordinator()
        defer { fixture.cleanUp(relaunched) }
        relaunched.now = { later }
        #expect(relaunched.restoreOpenNotes() == [id])

        #expect(try fixture.windowState(for: id)?.lastOpened == opened)
        // "모두 보이기"로 돌아온 창도 연 것이 아니다.
        relaunched.toggleAllHidden()
        relaunched.toggleAllHidden()
        #expect(try fixture.windowState(for: id)?.lastOpened == opened)
    }

    /// 겹친 차례와 연 때는 한 번에 쓴다. 맡지 않은 항목(접힘)은 그대로 둔다.
    @Test func recorderWritesOrderAndTimeTogether() throws {
        defer { fixture.cleanUp() }
        let store = try WindowStateStore(location: fixture.location)
        let recorder = WindowStateRecorder(store: store, log: { _ in })
        let id = NoteID(rawValue: "a")
        try store.set(NoteWindowState(isOpen: true, foldedLines: [2]), for: id)
        var writes = 0
        let observation = store.observe { writes += 1 }
        defer { observation.cancel() }

        recorder.recordFronted(id, openedAt: date(10))
        #expect(writes == 1)
        #expect(store.state(for: id) == NoteWindowState(
            isOpen: true, stackOrder: 1, foldedLines: [2], lastOpened: date(10)
        ))
        // 이미 맨 앞이고 적을 때가 없으면 쓰지 않는다.
        recorder.recordFronted(id)
        #expect(writes == 1)
    }
}
