import Foundation
import Models
import Store
import Testing
@testable import FloatingNotes

/// 접힌 줄을 로컬 창 상태에 적는 표기와, 밖에서 본문이 바뀌었을 때 줄 번호를 옮기는 규칙.
@Suite struct FoldPersistenceTests {
    private func restored(_ stored: (lines: [Int], texts: [String])?, in text: String) -> Set<Int> {
        FoldPersistence.restored(lines: stored?.lines, texts: stored?.texts, in: text)
    }

    @Test func storedFormIsSortedCarriesTheLineTextsAndEmptyMeansNoEntry() throws {
        let text = "+ 하나\n\t안\n+ 둘\n\t안\n끝\n+ 셋"
        let stored = try #require(FoldPersistence.stored([5, 0, 2], in: text))
        #expect(stored.lines == [0, 2, 5])
        #expect(stored.texts == ["+ 하나", "+ 둘", "+ 셋"])
        let none = FoldPersistence.stored([], in: text)
        // 본문에 없는 줄 번호는 적지 않는다.
        let outside = FoldPersistence.stored([-1, 99], in: text)
        #expect(none == nil && outside == nil)
    }

    /// 창이 닫힌 사이에 다른 프로그램이 위에 두 줄을 넣었다. 줄 번호만 믿으면 엉뚱한 토글이 접힌다.
    @Test func foldsFollowTheirLinesWhenTheFileChangedWhileTheWindowWasClosed() {
        let old = "제목\n+ 첫 토글\n\t안\n+ 접어 둔 토글\n\t안\n+ 셋째 토글\n\t안"
        let stored = FoldPersistence.stored([3], in: old)
        let new = "새 줄 하나\n새 줄 둘\n" + old

        #expect(restored(stored, in: new) == [5])
        // 그대로면 그대로, 끝에 줄이 붙어도(빠른 캡처) 그대로다.
        #expect(restored(stored, in: old) == [3])
        #expect(restored(stored, in: old + "\n- [ ] 붙은 줄") == [3])
        #expect(restored(stored, in: old + "\r\n붙은 줄") == [3])
    }

    @Test func foldsWhoseLineIsGoneAreDroppedAndTheRestStillMove() {
        let old = "+ 가\n\t안\n+ 나\n\t안\n+ 다\n\t안"
        let stored = FoldPersistence.stored([0, 2, 4], in: old)
        // "나" 토글의 글이 바뀌고, 맨 위에 한 줄이 들어왔다.
        let new = "새 줄\n+ 가\n\t안\n+ 나 고침\n\t안\n+ 다\n\t안"

        #expect(restored(stored, in: new) == [1, 5])
        #expect(restored(stored, in: "전혀 다른 글").isEmpty)
    }

    /// 같은 글의 토글이 여럿이면 어느 것인지 알 수 없다. 앞의 접힘이 얼마나 밀렸는지 알면 그만큼 밀린
    /// 자리의 것을 따르고, 모르면 엉뚱한 토글을 접지 않고 버린다.
    @Test func duplicateToggleTextsFollowAKnownShiftOrAreDropped() {
        let old = "+ 고유한 토글\n\t안\n+ 할 일\n\t하나\n+ 할 일\n\t둘"
        let new = "머리말\n" + old
        // 앞의 "고유한 토글"이 한 줄 밀린 것을 알므로 뒤의 것들도 한 줄 밀린 자리에서 찾는다.
        #expect(restored(FoldPersistence.stored([0, 2, 4], in: old), in: new) == [1, 3, 5])
        #expect(restored(FoldPersistence.stored([0, 4], in: old), in: new) == [1, 5])
        // 기준이 없으면 "할 일" 둘 가운데 어느 것인지 알 수 없다.
        #expect(restored(FoldPersistence.stored([4], in: old), in: new).isEmpty)
        // 한 줄이 두 접힘을 받지 않는다.
        let removed = "+ 할 일\n\t하나"
        #expect(FoldPersistence.restored(lines: [0, 2], texts: ["+ 할 일", "+ 할 일"], in: removed) == [0])
    }

    /// 줄의 글 없이 적힌 예전 상태 파일은 견줄 것이 없어 줄 번호를 그대로 쓴다.
    @Test func statesWrittenWithoutLineTextsFallBackToTheBareIndices() {
        #expect(FoldPersistence.restored(lines: [2, 0, 2, -3], texts: nil, in: "무엇이든") == [0, 2])
        #expect(FoldPersistence.restored(lines: [1], texts: ["짝이", "맞지 않음"], in: "무엇이든") == [1])
        #expect(FoldPersistence.restored(lines: nil, texts: nil, in: "무엇이든").isEmpty)
    }

    @Test func foldsAboveAnOutsideEditStayAndFoldsBelowMoveWithTheirLines() {
        let old = "가\n+ 위 토글\n\t안\n나\n+ 아래 토글\n\t안"
        // 가운데("나")에 두 줄이 더해졌다.
        let new = "가\n+ 위 토글\n\t안\n나\n새 줄 하나\n새 줄 둘\n+ 아래 토글\n\t안"
        #expect(FoldPersistence.remapped([1, 4], from: old, to: new) == [1, 6])
        // 거꾸로 줄이 빠지면 위로 올라온다.
        #expect(FoldPersistence.remapped([1, 6], from: new, to: old) == [1, 4])
    }

    @Test func foldsOnChangedLinesAreDropped() {
        let old = "+ 토글\n\t안\n끝"
        #expect(FoldPersistence.remapped([0], from: old, to: "토글 아님\n\t안\n끝").isEmpty)
        #expect(FoldPersistence.remapped([0], from: old, to: "전혀 다른 글").isEmpty)
        #expect(FoldPersistence.remapped([], from: old, to: "무엇이든").isEmpty)
    }

    @Test func sameTextAndOtherLineEndingsKeepEveryFold() {
        let old = "+ 하나\n\t안\n+ 둘\n\t안"
        #expect(FoldPersistence.remapped([0, 2], from: old, to: old) == [0, 2])
        #expect(FoldPersistence.remapped([0, 2], from: old, to: "+ 하나\r\n\t안\r\n+ 둘\r\n\t안") == [0, 2])
        // 끝에 줄이 붙어도 그대로다.
        #expect(FoldPersistence.remapped([0, 2], from: old, to: old + "\n덧붙인 줄") == [0, 2])
    }

    /// 접힘은 창 상태의 다른 항목(틀, 핀)을 건드리지 않고 그 항목만 고친다.
    @Test func storeWritesOnlyTheFoldedLinesOfTheWindowState() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fold-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let windowStates = try WindowStateStore(location: location)
        let id = NoteID(rawValue: "n")
        let frame = WindowFrame(x: 1, y: 2, width: 340, height: 100)
        try windowStates.set(NoteWindowState(frame: frame, isPinned: false, isOpen: true, stackOrder: 4), for: id)
        var logs: [String] = []
        let folds = NoteFoldStore(windowStates: windowStates) { logs.append($0) }

        let text = "머리\n+ 하나\n\t안\n+ 둘\n\t안"
        #expect(folds.foldedLines(for: id, in: text).isEmpty)
        #expect(!folds.hasStoredFolds(for: id))
        folds.save([3, 1], in: text, for: id)

        let reloaded = try WindowStateStore(location: location)
        #expect(reloaded.state(for: id) == NoteWindowState(
            frame: frame, isPinned: false, isOpen: true, stackOrder: 4, foldedLines: [1, 3],
            foldedLineTexts: ["+ 하나", "+ 둘"]
        ))
        let reopened = NoteFoldStore(windowStates: reloaded, log: { _ in })
        #expect(reopened.hasStoredFolds(for: id))
        #expect(reopened.foldedLines(for: id, in: text) == [1, 3])
        #expect(reopened.foldedLines(for: id, in: "새 줄\n" + text) == [2, 4])
        folds.save([], in: text, for: id)
        let cleared = try WindowStateStore(location: location).state(for: id)
        #expect(cleared?.foldedLines == nil)
        #expect(cleared?.foldedLineTexts == nil)
        #expect(logs.isEmpty)
    }
}
