import CoreGraphics
import Foundation
import Models
import Routing
import Testing
@testable import Browse

/// 고른 줄 옮기기, 여는 요청, 떠 있는 노트, 리마인더 글자, 놓이는 자리(spec 4.1, 8).
@Suite struct BrowseLogicTests {
    private let entries = BrowseContent(
        notes: Sample.notes, floating: Sample.floating, lastOpened: Dictionary(uniqueKeysWithValues: Sample.notes.map { ($0.note.id, TestClock.now) }), query: BrowseQuery(""), excluding: nil
    ).entries

    // MARK: - ↑↓

    @Test func selectionStartsAtTheFirstRow() {
        // 0은 구획 이름이다.
        #expect(BrowseSelection.initial(in: entries) == 1)
        #expect(BrowseSelection.initial(in: [.library]) == 0)
        #expect(BrowseSelection.initial(in: [.header("x"), .separator]) == nil)
    }

    /// 목록을 다시 만든 뒤에도 고른 줄은 같은 노트다. 줄의 내용(제목, 본문 첫머리, 리마인더)이 바뀌어도 그렇다.
    @Test func selectionIsKeptByNoteIDNotByRowContent() {
        let changed = Sample.notes.map { indexed in
            indexed.note.id.rawValue == "release"
                ? Sample.note("release", title: "새 제목", body: "새 본문\n", space: Sample.work, reminder: nil)
                : indexed
        }
        let rebuilt = BrowseContent(
            notes: changed, floating: Sample.floating, lastOpened: Dictionary(uniqueKeysWithValues: Sample.notes.map { ($0.note.id, TestClock.now) }), query: BrowseQuery(""), excluding: nil
        ).entries
        let selected = entries[4]
        #expect(selected.label == "release")
        // 줄 전체로 견주면 같은 줄이 없다.
        #expect(!rebuilt.contains(selected))
        #expect(BrowseSelection.index(keeping: selected, in: rebuilt) == 4)
        // 노트가 아닌 줄은 같은 줄로, 없어진 줄과 고른 것이 없을 때는 맨 윗줄로.
        #expect(BrowseSelection.index(keeping: .library, in: rebuilt) == 9)
        #expect(BrowseSelection.index(keeping: .create(query: "x"), in: rebuilt) == 1)
        #expect(BrowseSelection.index(keeping: nil, in: rebuilt) == 1)
        let withoutIt = BrowseContent(
            notes: Sample.notes.filter { $0.note.id.rawValue != "release" }, floating: Sample.floating, lastOpened: Dictionary(uniqueKeysWithValues: Sample.notes.map { ($0.note.id, TestClock.now) }),
            query: BrowseQuery(""), excluding: nil
        ).entries
        #expect(BrowseSelection.index(keeping: selected, in: withoutIt) == 1)
    }

    @Test func arrowsSkipHeadersAndTheSeparatorAndStopAtTheEnds() {
        // 0 이름, 1~3 떠 있는 노트, 4 이름, 5~8 최근, 9 구분선, 10 라이브러리.
        #expect(entries.count == 10)
        #expect(BrowseSelection.moved(from: 1, by: 1, in: entries) == 2)
        #expect(BrowseSelection.moved(from: 3, by: 1, in: entries) == 4)
        #expect(BrowseSelection.moved(from: 4, by: -1, in: entries) == 3)
        #expect(BrowseSelection.moved(from: 7, by: 1, in: entries) == 9)
        #expect(BrowseSelection.moved(from: 9, by: -1, in: entries) == 7)
        #expect(BrowseSelection.moved(from: 9, by: 1, in: entries) == 9)
        #expect(BrowseSelection.moved(from: 1, by: -1, in: entries) == 1)
    }

    @Test func movingWithoutASelectionStartsFromAnEnd() {
        #expect(BrowseSelection.moved(from: nil, by: 1, in: entries) == 1)
        #expect(BrowseSelection.moved(from: nil, by: -1, in: entries) == 9)
        // 고를 수 없는 줄을 가리키고 있어도 같다.
        #expect(BrowseSelection.moved(from: 8, by: 1, in: entries) == 1)
        #expect(BrowseSelection.moved(from: 1, by: 1, in: [.header("x")]) == nil)
    }

    @Test func walkingDownVisitsEveryRowInOrder() {
        var index = BrowseSelection.initial(in: entries)
        var visited: [String] = []
        while let current = index {
            visited.append(entries[current].label)
            let next = BrowseSelection.moved(from: current, by: 1, in: entries)
            if next == current { break }
            index = next
        }
        #expect(visited == ["today", "home", "scratch", "release", "untitled", "meeting", "api", "library"])
    }

    // MARK: - 여는 요청

    @Test func rowsRouteThroughTheRouter() throws {
        let current = NoteID(rawValue: "today")
        let noteEntry = entries[2]
        #expect(BrowseSelection.route(for: noteEntry, current: current) == .openNote(NoteID(rawValue: "home")))
        #expect(BrowseSelection.route(for: .library, current: current) == .openLibrary)
        #expect(BrowseSelection.route(for: .create(query: "새 일"), current: current)
            == .newNote(NewNoteRequest(draft: NoteDraft(title: "새 일"), nextTo: current)))
        #expect(BrowseSelection.route(for: .create(query: "새 일"), current: nil)
            == .newNote(NewNoteRequest(draft: NoteDraft(title: "새 일"), nextTo: nil)))
        #expect(BrowseSelection.route(for: .header("x"), current: current) == nil)
        #expect(BrowseSelection.route(for: .separator, current: current) == nil)
    }

    // MARK: - 떠 있는 노트

    @Test func floatingNotesAreTheOpenWindowsFrontFirst() {
        let states: [NoteID: NoteWindowState] = [
            NoteID(rawValue: "back"): NoteWindowState(isOpen: true, stackOrder: 1),
            NoteID(rawValue: "front"): NoteWindowState(isOpen: true, stackOrder: 7),
            NoteID(rawValue: "closed"): NoteWindowState(isOpen: false, stackOrder: 9),
            NoteID(rawValue: "middle"): NoteWindowState(isPinned: false, isOpen: true, stackOrder: 3),
            NoteID(rawValue: "b-unordered"): NoteWindowState(isOpen: true),
            NoteID(rawValue: "a-unordered"): NoteWindowState(isOpen: true),
        ]
        #expect(BrowseFloating.ids(from: states).map(\.rawValue)
            == ["front", "back", "a-unordered", "b-unordered"])
        #expect(BrowseFloating.ids(from: [:]).isEmpty)
    }

    // MARK: - 자리

    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func anchor(_ frame: CGRect) -> BrowsePlacement.Anchor {
        BrowsePlacement.Anchor(frame: frame, chromeHeight: 28, gap: 2, inset: 24)
    }

    /// 노트 상단 줄 아래, 노트 오른쪽 끝에서 24 들어간 자리에 오른쪽을 맞춘다(시안의 배치).
    @Test func anchoredPanelHangsBelowTheNoteTopRow() {
        let note = CGRect(x: 600, y: 500, width: 340, height: 300)
        let topLeft = BrowsePlacement.topLeft(
            width: 300, anchor: anchor(note), visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6
        )
        #expect(topLeft == CGPoint(x: 616, y: 770))
        #expect(BrowsePlacement.frame(topLeft: topLeft, width: 300, height: 200)
            == CGRect(x: 616, y: 570, width: 300, height: 200))
    }

    @Test func anchoredPanelIsPushedBackOntoTheScreen() {
        let atLeftEdge = CGRect(x: -100, y: 500, width: 340, height: 300)
        #expect(BrowsePlacement.topLeft(
            width: 300, anchor: anchor(atLeftEdge), visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6
        ).x == 0)
        let atRightEdge = CGRect(x: 1500, y: 500, width: 340, height: 300)
        #expect(BrowsePlacement.topLeft(
            width: 300, anchor: anchor(atRightEdge), visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6
        ).x == 1300)
        let aboveTheScreen = CGRect(x: 600, y: 900, width: 340, height: 300)
        #expect(BrowsePlacement.topLeft(
            width: 300, anchor: anchor(aboveTheScreen), visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6
        ).y == 1000)
    }

    /// 노트가 화면 아래쪽에 있으면 목록이 위로 올라가 뜬다. 높이 한도만큼의 자리가 늘 남는다.
    @Test func anchoredPanelKeepsRoomForItsRows() {
        let lowNote = CGRect(x: 600, y: 20, width: 340, height: 120)
        let topLeft = BrowsePlacement.topLeft(
            width: 300, anchor: anchor(lowNote), visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6
        )
        #expect(topLeft.y == 600)
        #expect(BrowsePlacement.maxHeight(top: topLeft.y, visibleFrame: visible, heightRatio: 0.6) == 600)
    }

    /// 앵커가 없으면 화면 가운데, 위에서 22%다.
    @Test func unanchoredPanelUsesTheCaptureBarPosition() {
        let topLeft = BrowsePlacement.topLeft(width: 300, anchor: nil, visibleFrame: visible, topRatio: 0.22, heightRatio: 0.6)
        #expect(topLeft == CGPoint(x: 650, y: 780))
    }

    @Test func heightIsLimitedByTheScreenShareAndTheSpaceBelow() {
        #expect(BrowsePlacement.maxHeight(top: 780, visibleFrame: visible, heightRatio: 0.6) == 600)
        #expect(BrowsePlacement.maxHeight(top: 250, visibleFrame: visible, heightRatio: 0.6) == 250)
        #expect(BrowsePlacement.maxHeight(top: -10, visibleFrame: visible, heightRatio: 0.6) == 0)
    }
}
