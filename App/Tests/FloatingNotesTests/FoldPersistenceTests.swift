import Foundation
import Models
import Store
import Testing
@testable import FloatingNotes

/// 접힌 줄을 로컬 창 상태에 적는 표기와, 밖에서 본문이 바뀌었을 때 줄 번호를 옮기는 규칙.
@Suite struct FoldPersistenceTests {
    @Test func storedFormIsSortedAndEmptyMeansNoEntry() {
        #expect(FoldPersistence.stored([5, 0, 2]) == [0, 2, 5])
        #expect(FoldPersistence.stored([]) == nil)
        #expect(FoldPersistence.stored([-1]) == nil)
        #expect(FoldPersistence.lines(from: [2, 0, 2, -3]) == [0, 2])
        #expect(FoldPersistence.lines(from: nil).isEmpty)
    }

    @Test func foldsAboveAnOutsideEditStayAndFoldsBelowMoveWithTheirLines() {
        let old = "가\n> 위 토글\n\t안\n나\n> 아래 토글\n\t안"
        // 가운데("나")에 두 줄이 더해졌다.
        let new = "가\n> 위 토글\n\t안\n나\n새 줄 하나\n새 줄 둘\n> 아래 토글\n\t안"
        #expect(FoldPersistence.remapped([1, 4], from: old, to: new) == [1, 6])
        // 거꾸로 줄이 빠지면 위로 올라온다.
        #expect(FoldPersistence.remapped([1, 6], from: new, to: old) == [1, 4])
    }

    @Test func foldsOnChangedLinesAreDropped() {
        let old = "> 토글\n\t안\n끝"
        #expect(FoldPersistence.remapped([0], from: old, to: "토글 아님\n\t안\n끝").isEmpty)
        #expect(FoldPersistence.remapped([0], from: old, to: "전혀 다른 글").isEmpty)
        #expect(FoldPersistence.remapped([], from: old, to: "무엇이든").isEmpty)
    }

    @Test func sameTextAndOtherLineEndingsKeepEveryFold() {
        let old = "> 하나\n\t안\n> 둘\n\t안"
        #expect(FoldPersistence.remapped([0, 2], from: old, to: old) == [0, 2])
        #expect(FoldPersistence.remapped([0, 2], from: old, to: "> 하나\r\n\t안\r\n> 둘\r\n\t안") == [0, 2])
        // 끝에 줄이 붙어도 그대로다.
        #expect(FoldPersistence.remapped([0, 2], from: old, to: old + "\n덧붙인 줄") == [0, 2])
    }

    /// 접힘은 창 상태의 다른 항목(틀, 핀)을 건드리지 않고 그 항목만 고친다.
    @Test func storeWritesOnlyTheFoldedLinesOfTheWindowState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fold-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let windowStates = try WindowStateStore(location: location)
        let id = NoteID(rawValue: "n")
        let frame = WindowFrame(x: 1, y: 2, width: 340, height: 100)
        try windowStates.set(NoteWindowState(frame: frame, isPinned: false, isOpen: true, stackOrder: 4), for: id)
        var logs: [String] = []
        let folds = NoteFoldStore(windowStates: windowStates) { logs.append($0) }

        #expect(folds.foldedLines(for: id).isEmpty)
        folds.save([3, 1], for: id)

        let reloaded = try WindowStateStore(location: location)
        #expect(reloaded.state(for: id) == NoteWindowState(
            frame: frame, isPinned: false, isOpen: true, stackOrder: 4, foldedLines: [1, 3]
        ))
        #expect(NoteFoldStore(windowStates: reloaded, log: { _ in }).foldedLines(for: id) == [1, 3])
        folds.save([], for: id)
        #expect(try WindowStateStore(location: location).state(for: id)?.foldedLines == nil)
        #expect(logs.isEmpty)
    }
}
