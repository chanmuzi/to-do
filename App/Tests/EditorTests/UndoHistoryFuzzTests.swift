import Foundation
import Testing
@testable import Editor

/// 되돌리기 기록의 위치 옮기기를 무작위로 두드린다(편집기 없이 `UndoHistory`만).
///
/// 글자마다 다른 글자를 쓰므로 무엇이 어디로 갔는지 정확히 볼 수 있다. 지켜져야 하는 것:
/// - 되돌리거나 다시 하는 단계마다 적어 둔 글이 그 자리에 그대로 있다.
/// - 한 번이라도 함께 있었던 두 글자의 앞뒤는 뒤바뀌지 않는다(기록을 버린 경우에도. 글이 엉뚱한 자리에 놓이지 않는다).
/// - 문서 끝에 덧붙인 글 뒤에는 그보다 먼저 생긴 글자가 오지 않고, 맨 앞에 붙인 글 앞에도 오지 않는다.
/// - 기록을 버린 적이 없으면: 모두 되돌린 글은 처음 글에 바깥의 변경만 든 것이고, 모두 다시 하면 되돌리기 전의 글이다.
@Suite struct UndoHistoryFuzzTests {
    typealias Generator = EditorFuzzTests.Generator

    struct Model {
        var text: [unichar] = []
        var history = UndoHistory()
        var nextScalar: unichar = 0x4E00
        /// 글자가 생긴 차례.
        var birth: [unichar: Int] = [:]
        var clock = 0
        /// 문서 끝에 덧붙인 글(맨 앞에 붙인 글)과 그때의 차례.
        var appends: [(units: Set<unichar>, time: Int)] = []
        var prepends: [(units: Set<unichar>, time: Int)] = []
        var snapshots: [[unichar]] = []
        var dropped = false
        var outsideInserted: Set<unichar> = []
        var outsideDeleted: Set<unichar> = []
        var failure: String?

        var string: String { String(utf16CodeUnits: text, count: text.count) }

        mutating func fresh(_ count: Int) -> [unichar] {
            clock += 1
            return (0..<count).map { _ in
                defer { nextScalar += 1 }
                birth[nextScalar] = clock
                return nextScalar
            }
        }

        mutating func snapshot() {
            if snapshots.last != text { snapshots.append(text) }
        }

        mutating func userEdit(_ random: inout Generator) {
            let caret = NSRange(location: 0, length: 0)
            history.close(selectionAfter: caret, coalescesTyping: false)
            var record = UndoRecord(selectionBefore: caret, selectionAfter: caret)
            for _ in 0...random.below(3) {
                let location = random.below(text.count + 1)
                let length = min(random.below(4), text.count - location)
                let inserted = fresh(length == 0 ? 1 + random.below(3) : random.below(3))
                let old = Array(text[location..<(location + length)])
                text.replaceSubrange(location..<(location + length), with: inserted)
                record.edits.append(UndoEdit(
                    location: location,
                    old: String(utf16CodeUnits: old, count: old.count),
                    new: String(utf16CodeUnits: inserted, count: inserted.count)
                ))
            }
            record.isTyping = record.edits.count == 1 && record.edits[0].old.isEmpty && random.below(2) == 0
            history.open = record
            // 열린 단계가 있는 채로 바깥의 변경이 들어오는 경우도 본다.
            if random.below(4) > 0 { history.close(selectionAfter: caret, coalescesTyping: random.below(2) == 0) }
        }

        mutating func replay(redo: Bool) {
            history.close(selectionAfter: NSRange(location: 0, length: 0), coalescesTyping: false)
            guard let record = redo ? history.redoStack.popLast() : history.undoStack.popLast() else { return }
            guard UndoHistory.matches(record, in: string, redo: redo) else {
                failure = "적어 둔 글이 그 자리에 없다(\(redo ? "다시 하기" : "되돌리기"))"
                return
            }
            for edit in redo ? record.edits : record.edits.reversed() {
                let length = redo ? edit.oldLength : edit.newLength
                text.replaceSubrange(edit.location..<(edit.location + length), with: Array((redo ? edit.new : edit.old).utf16))
            }
            if redo { history.pushUndo(record) } else { history.redoStack.append(record) }
        }

        mutating func outside(_ random: inout Generator) {
            var range: NSRange
            var inserted: [unichar]
            switch random.below(10) {
            case 0, 1, 2:
                range = NSRange(location: text.count, length: 0)
                inserted = fresh(1 + random.below(3))
                // 빈 문서에 넣은 글은 덧붙인 것으로 본다.
                appends.append((Set(inserted), clock))
            case 3:
                range = NSRange(location: 0, length: 0)
                inserted = fresh(1 + random.below(3))
                if text.isEmpty { appends.append((Set(inserted), clock)) } else { prepends.append((Set(inserted), clock)) }
            case 4, 5, 6:
                range = NSRange(location: random.below(text.count + 1), length: 0)
                inserted = fresh(1 + random.below(2))
            case 7:
                let location = random.below(text.count + 1)
                range = NSRange(location: location, length: min(1 + random.below(3), text.count - location))
                inserted = []
            case 8:
                let location = random.below(text.count + 1)
                range = NSRange(location: location, length: min(random.below(4), text.count - location))
                inserted = fresh(1 + random.below(2))
            default:
                range = NSRange(location: 0, length: text.count)
                inserted = fresh(2)
            }
            guard range.length > 0 || !inserted.isEmpty else { return }
            let before = history.undoStack.count + history.redoStack.count + (history.open == nil ? 0 : 1)
            if range.location == 0, range.length == text.count, !text.isEmpty {
                history = UndoHistory()
            } else {
                history.shift(outside: range, delta: inserted.count - range.length, documentLength: text.count)
            }
            if history.undoStack.count + history.redoStack.count + (history.open == nil ? 0 : 1) < before { dropped = true }
            outsideDeleted.formUnion(text[range.location..<NSMaxRange(range)])
            outsideInserted.formUnion(inserted)
            text.replaceSubrange(range.location..<NSMaxRange(range), with: inserted)
        }

        /// 지금 글에서 지켜져야 하는 앞뒤.
        func orderProblem() -> String? {
            let position = Dictionary(uniqueKeysWithValues: text.enumerated().map { ($1, $0) })
            for append in appends {
                guard let first = append.units.compactMap({ position[$0] }).min() else { continue }
                if text[first...].contains(where: { (birth[$0] ?? 0) < append.time }) { return "덧붙인 글 뒤에 그보다 먼저 생긴 글자가 있다" }
            }
            for prepend in prepends {
                guard let last = prepend.units.compactMap({ position[$0] }).max() else { continue }
                if text[...last].contains(where: { (birth[$0] ?? 0) < prepend.time }) { return "맨 앞에 붙인 글 앞에 그보다 먼저 생긴 글자가 있다" }
            }
            return nil
        }

        /// 한 번이라도 함께 있었던 글자들의 앞뒤가 그대로인지.
        func keepsEveryObservedOrder() -> Bool {
            let present = Set(text)
            return snapshots.allSatisfy { snapshot in
                let members = Set(snapshot)
                return snapshot.filter(present.contains) == text.filter(members.contains)
            }
        }
    }

    private func run(seed: UInt64, sequences: Int) -> (mismatches: Int, dropped: Int) {
        var random = Generator(state: seed)
        var mismatches = 0
        var droppedSequences = 0
        for sequence in 0..<sequences {
            var model = Model()
            model.text = model.fresh(random.below(12))
            let original = model.text
            model.snapshot()
            var log: [String] = []
            func fail(_ what: String) {
                mismatches += 1
                if mismatches <= 5 { Issue.record("\(what): seed \(seed) #\(sequence) \(log.joined(separator: " "))") }
            }
            var failed = false
            for _ in 0..<(8 + random.below(30)) where !failed {
                switch random.below(10) {
                case 0..<4:
                    model.userEdit(&random)
                    log.append("edit")
                case 4, 5:
                    model.replay(redo: false)
                    log.append("undo")
                case 6:
                    model.replay(redo: true)
                    log.append("redo")
                default:
                    model.outside(&random)
                    log.append("outside")
                }
                model.snapshot()
                if let problem = model.failure ?? model.orderProblem() {
                    fail(problem)
                    failed = true
                }
            }
            guard !failed else { continue }
            let beforeUndo = model.text
            model.history.close(selectionAfter: NSRange(location: 0, length: 0), coalescesTyping: false)
            var undone = 0
            while !model.history.undoStack.isEmpty, model.failure == nil {
                model.replay(redo: false)
                undone += 1
            }
            let base = model.text
            let baseProblem = model.failure ?? model.orderProblem() ?? (model.keepsEveryObservedOrder() ? nil : "모두 되돌린 글에서 글자의 앞뒤가 바뀌었다")
            // 되돌린 만큼만 다시 한다(그 전에 되돌려 둔 단계는 건드리지 않는다).
            for _ in 0..<undone where model.failure == nil { model.replay(redo: true) }
            if let problem = baseProblem ?? model.failure {
                fail(problem)
                continue
            }
            guard model.text == beforeUndo else {
                fail("모두 다시 해도 되돌리기 전의 글이 아니다")
                continue
            }
            if model.dropped {
                droppedSequences += 1
            } else if Set(base) != Set(original).union(model.outsideInserted).subtracting(model.outsideDeleted) {
                fail("모두 되돌린 글이 처음 글에 바깥의 변경만 든 것이 아니다")
            }
        }
        return (mismatches, droppedSequences)
    }

    @Test(arguments: [101, 102, 103, 104] as [UInt64])
    func shiftedHistoryNeverMisplacesText(seed: UInt64) {
        let environment = ProcessInfo.processInfo.environment
        let sequences = environment["UNDO_FUZZ_SEQUENCES"].flatMap(Int.init) ?? 1_500
        let result = run(seed: environment["UNDO_FUZZ_SEED"].flatMap(UInt64.init).map { $0 &+ seed } ?? seed, sequences: sequences)
        #expect(result.mismatches == 0)
        if environment["UNDO_FUZZ_SEQUENCES"] != nil {
            print("UNDO_FUZZ seed \(seed): \(sequences) sequences, \(result.mismatches) mismatches, \(result.dropped) with dropped history")
        }
    }
}
