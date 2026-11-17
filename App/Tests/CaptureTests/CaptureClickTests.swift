import AppKit
import Models
import Routing
import Testing
@_spi(Verification) @testable import Capture

/// 캡처 바를 실제 마우스 이벤트로 누른다. 바 안을 누르면 닫히지 않고 적은 글이 그대로이며, 다시 ↵로 넣을 수 있다.
@MainActor
@Suite(.serialized) struct CaptureClickTests {
    private let fixture: CaptureFixture
    private let capture: CaptureCoordinator

    init() throws {
        fixture = try CaptureFixture()
        capture = fixture.makeCoordinator()
    }

    private func click(at location: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!)
        }
    }

    @Test func pressingInsideTheBarKeepsItOpenWithTheText() throws {
        defer { fixture.cleanUp() }
        capture.show()
        let window = try #require(capture.window)
        let input = try #require(capture.inputView)
        input.type("우유 사기")
        let bounds = try #require(window.contentView).bounds
        for x in stride(from: 4.0, through: bounds.width - 4, by: 40) {
            click(at: NSPoint(x: x, y: bounds.midY), in: window)
        }
        #expect(capture.isVisible)
        #expect(input.string == "우유 사기")
    }

    /// ↵로 넣으면 줄이 들어간 노트를 한 번 알린다(App이 짧은 알림을 띄운다, D-041). 넣지 못하면 알리지 않는다.
    @Test func capturedNoteIsReportedOnceAfterASuccessfulReturn() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘 할 일", body: "", spaceID: CaptureFixture.work.id))
        var reported: [NoteID] = []
        capture.onCaptured = { reported.append($0) }
        capture.now = { note.created }
        capture.show()
        try #require(capture.inputView).type("배포")
        try #require(capture.inputView).doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(reported == [note.id])
        #expect(!capture.isVisible)
    }
}
