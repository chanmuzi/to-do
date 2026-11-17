import AppKit
import Models
import Routing
import Testing
@_spi(Verification) @testable import Browse

/// 노트 찾기의 줄을 실제 마우스 이벤트(누름과 뗌)로 창의 이벤트 길에 넣어 누른다.
/// 시험의 노트 찾기는 키 창이 아니다: 키 창이 아닌 창의 첫 누름도 줄을 연다(`acceptsFirstMouse`).
@MainActor
@Suite(.serialized) struct BrowseClickTests {
    private let fixture: BrowseFixture
    private let browse: BrowseCoordinator
    private let ids: [NoteID]

    init() throws {
        fixture = try BrowseFixture()
        ids = [
            try fixture.add("셋째", body: "다", space: Sample.work),
            try fixture.add("", body: "제목 없는 노트", space: nil),
            try fixture.add("첫째", body: "가", space: Sample.home),
        ]
        browse = fixture.makeCoordinator()
    }

    private func click(_ view: NSView, at point: NSPoint, in window: NSWindow) {
        let location = view.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!)
        }
    }

    private func noteRows(in window: NSWindow) -> [BrowseNoteRowView] {
        func rows(in view: NSView) -> [BrowseNoteRowView] {
            view.subviews.flatMap { ($0 as? BrowseNoteRowView).map { [$0] } ?? rows(in: $0) }
        }
        return window.contentView.map(rows) ?? []
    }

    /// 줄의 어느 자리(아이콘, 제목, 본문 첫머리, 빈 곳)를 눌러도 그 노트가 한 번 열린다.
    @Test func everyNoteRowOpensItsNoteOnASingleRealPress() throws {
        defer { fixture.cleanUp() }
        for index in 0..<3 {
            browse.show(anchoredTo: nil, excluding: nil)
            let window = try #require(browse.window)
            window.contentView?.layoutSubtreeIfNeeded()
            let row = noteRows(in: window)[index]
            let target = row.noteRow.id
            let x = [CGFloat(6), row.bounds.midX, row.bounds.width - 6][index]
            click(row, at: NSPoint(x: x, y: row.bounds.midY), in: window)
            #expect(fixture.routes.last == .openNote(target))
            #expect(fixture.routes.count == index + 1)
            browse.hide()
        }
    }

    /// 제목이 없는 노트와 스페이스가 없는 노트의 제목도 아이콘이 있는 줄과 같은 자리에서 시작한다.
    @Test func titlesStartAtTheSameXWithOrWithoutASpaceIcon() throws {
        defer { fixture.cleanUp() }
        browse.show(anchoredTo: nil, excluding: nil)
        let window = try #require(browse.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let starts = Set(noteRows(in: window).map(\.titleFrame.minX))
        #expect(starts.count == 1, "\(starts)")
    }
}
