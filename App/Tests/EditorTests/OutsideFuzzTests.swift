import AppKit
import Testing
@testable import Editor

/// 사용자의 편집, 되돌리기와 다시 하기, 한글 조합 사이사이에 바깥의 변경(빠른 캡처가 붙인 줄, 다른 프로그램이
/// 고친 글)을 무작위로 끼워 넣는다. 묶음을 직접 여는 방식과 런 루프 한 차례가 한 단계인 방식 둘 다로 돌린다.
///
/// 지켜져야 하는 것(D-037):
/// - 되돌리거나 다시 하는 단계마다 적어 둔 글이 그 자리에 그대로 있다(어긋나면 `EditorHarness`가 실패로 적는다).
/// - 모두 되돌린 뒤 그만큼 다시 하면 되돌리기 전의 원문이다.
/// - 기록을 버린 적이 없으면, 모두 되돌린 글의 글자들은 처음 글에 바깥이 넣고 뺀 글자만 더한 것이다.
/// - 바깥의 변경이 끝에 붙이거나 맨 앞에 붙인 것뿐이면 기록을 버리지 않고, 모두 되돌린 글은 처음 글의 앞뒤에
///   그 글들이 붙은 것과 꼭 같다.
@MainActor
@Suite struct OutsideFuzzTests {
    typealias Generator = EditorFuzzTests.Generator

    struct Outcome {
        var sequences = 0
        var mismatches = 0
        var dropped = 0
        var exact = 0
    }

    /// 메인 큐에 쌓인 일(되돌리기 단계 닫기, 미뤄 둔 알림)이 지나가게 한다. 런 루프 한 차례에 해당한다.
    private func turn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func counts(_ text: String) -> [unichar: Int] {
        var result: [unichar: Int] = [:]
        for unit in text.utf16 { result[unit, default: 0] += 1 }
        return result
    }

    /// 바깥의 변경 하나. 한 일을 글자로 돌려준다. `expected`는 끝이나 맨 앞에 붙이는 변경만 있었을 때의
    /// "처음 글에 바깥의 변경만 든 글"이고, 그 밖의 변경이 끼면 `nil`이 된다.
    private func outside(
        _ h: EditorHarness, _ random: inout Generator, counter: inout Int, expected: inout String?, onlyEdges: Bool
    ) -> String {
        counter += 1
        // 다른 어디에도 없는 글자로 시작하게 해서, 달라진 부분이 넣은 자리 그대로 잡히게 한다.
        let tag = String(UnicodeScalar(UInt32(0x4E00 + counter % 20_000)).map(Character.init) ?? "丁")
        let text = h.editor.text
        let whole = text as NSString
        let caret = min(h.editor.selectedRange.location, whole.length)
        func insert(_ string: String, at location: Int) -> String {
            whole.replacingCharacters(in: NSRange(location: location, length: 0), with: string)
        }
        switch random.below(onlyEdges ? 5 : 14) {
        case 0, 1, 2, 3:
            let suffix = random.pick(["\n[ ] \(tag)\n", "[ ] \(tag)", "\r\n\(tag)\r\n", tag, "\(tag)\n"])
            expected = expected.map { $0 + LineEndings.normalized(suffix) }
            h.editor.appendFromOutside(suffix)
            return "append(\(suffix.debugDescription))"
        case 4:
            let prefix = "\(tag) 머리\n"
            // 빈 문서에 넣은 글은 덧붙인 것이다.
            expected = expected.map { text.isEmpty ? $0 + prefix : prefix + $0 }
            h.editor.applyOutsideChange(to: prefix + text)
            return "prepend(\(prefix.debugDescription))"
        case 5, 6:
            let location = min(max(caret + random.below(3) - 1, 0), whole.length)
            expected = nil
            h.editor.applyOutsideChange(to: insert(tag, at: location))
            return "insertNearCaret(\(location))"
        case 7, 8:
            let location = random.below(whole.length + 1)
            expected = nil
            h.editor.applyOutsideChange(to: insert(tag, at: location))
            return "insert(\(location))"
        case 9, 10:
            let lines = MarkdownDocument(text).lines
            let line = lines[random.below(lines.count)]
            expected = nil
            h.editor.applyOutsideChange(to: insert("\(tag) 새 줄\n", at: line.start))
            return "insertLine(\(line.start))"
        case 11:
            let lines = MarkdownDocument(text).lines
            let line = lines[random.below(lines.count)]
            expected = nil
            h.editor.applyOutsideChange(to: whole.replacingCharacters(in: line.fullRange, with: ""))
            return "deleteLine(\(line.start))"
        case 12:
            // 빠른 캡처: 끝의 빈 줄을 걷어 내고 한 줄을 붙인다.
            var body = text
            while body.hasSuffix("\n") { body.removeLast() }
            expected = nil
            h.editor.applyOutsideChange(to: body + (body.isEmpty ? "" : "\n") + "[ ] \(tag)\n")
            return "capture"
        default:
            expected = nil
            h.editor.applyOutsideChange(to: "\(tag) 통째로 다른 글\n둘째 줄")
            return "replaceAll"
        }
    }

    /// 조합 중일 때의 한 걸음.
    private func composing(_ h: EditorHarness, _ random: inout Generator) -> String {
        switch random.below(10) {
        case 0..<4:
            let next = random.pick(["ㅎ", "하", "한", "ㄱ"])
            h.mark(next)
            return "mark(\(next))"
        case 4..<7:
            let text = random.pick(["한", "가"])
            h.commit(text)
            return "commit(\(text))"
        case 7:
            h.step { h.view.unmarkText() }
            return "unmark"
        case 8:
            h.mark("")
            return "cancel"
        default:
            if random.below(2) == 0 { h.undo() } else { h.redo() }
            return "undoOrRedoWhileComposing"
        }
    }

    private func run(seed: UInt64, sequences: Int, steps: Int, runLoop: Bool, onlyEdges: Bool) async throws -> Outcome {
        var random = Generator(state: seed)
        var outcome = Outcome()
        for sequence in 0..<sequences {
            outcome.sequences += 1
            let original = random.pick(EditorFuzzTests.documents)
            let h = try EditorHarness(original)
            if runLoop {
                h.groupsSteps = false
                h.editor.undoManager.groupsByEvent = true
            }
            h.caret(at: random.below(h.document.length + 1))
            var expected: String? = original
            var balance = counts(original)
            var counter = sequence * 100
            var log: [String] = []
            var problem: String?
            // 조합 중이어서 미뤄 둔 변경이 있는데 또 변경이 왔다. 둘은 한 범위로 합쳐지므로(D-037의 4번) 그 사이의
            // 기록을 버릴 수 있다.
            var stacked = false
            let traces = ProcessInfo.processInfo.environment["FUZZ_TRACE"] == "\(seed):\(sequence)"
            for _ in 0..<steps where problem == nil {
                if random.below(10) < 3 {
                    let before = counts(h.editor.text)
                    if h.controller.deferredOutsideEdit != nil { stacked = true }
                    log.append(outside(h, &random, counter: &counter, expected: &expected, onlyEdges: onlyEdges))
                    for (unit, count) in counts(h.editor.text) { balance[unit, default: 0] += count }
                    for (unit, count) in before { balance[unit, default: 0] -= count }
                } else if h.view.hasMarkedText() {
                    log.append(composing(h, &random))
                } else if random.below(12) == 0 {
                    h.mark("ㅎ")
                    log.append("mark(ㅎ)")
                } else {
                    log.append(EditorFuzzTests.step(h, &random, wild: false))
                }
                // 런 루프 방식에서는 때때로 여러 걸음이 한 차례에 들어간다.
                if runLoop, random.below(4) > 0 { await turn() }
                if traces { print("TRACE \(log.last ?? "") → \(h.marked.debugDescription)") }
                if h.view.string != h.document.text { problem = "화면과 원문이 다르다" }
                if !h.replayMismatches.isEmpty { problem = "되돌리기 기록이 원문과 어긋났다" }
            }
            if problem == nil {
                if h.view.hasMarkedText() { h.step { h.view.unmarkText() } }
                await turn()
                h.controller.flushPendingChangeNow()
                h.controller.closeUndoRecord()
                if h.controller.deferredOutsideEdit != nil { problem = "미뤄 둔 바깥의 변경이 남았다" }
            }
            if problem == nil {
                let beforeUndo = h.editor.text
                var undone = 0
                while h.editor.undoManager.canUndo, undone < 10_000 {
                    h.undo()
                    undone += 1
                }
                let base = h.editor.text
                for _ in 0..<undone { h.redo() }
                let dropped = h.controller.historyDropCount > 0
                if !h.replayMismatches.isEmpty {
                    problem = "되돌리기 기록이 원문과 어긋났다"
                } else if h.editor.text != beforeUndo {
                    problem = "모두 다시 해도 되돌리기 전의 원문이 아니다 \(h.editor.text.debugDescription) ≠ \(beforeUndo.debugDescription)"
                } else if !dropped, counts(base).filter({ $0.value != 0 }) != balance.filter({ $0.value != 0 }) {
                    problem = "모두 되돌린 글이 처음 글에 바깥의 변경만 든 것이 아니다 \(base.debugDescription)"
                } else if let expected {
                    if dropped {
                        if !stacked { problem = "끝이나 맨 앞에 붙였을 뿐인데 기록을 버렸다" }
                    } else if base != expected {
                        problem = "모두 되돌린 글이 다르다 \(base.debugDescription) ≠ \(expected.debugDescription)"
                    } else {
                        outcome.exact += 1
                    }
                }
                if dropped { outcome.dropped += 1 }
            }
            if let problem {
                outcome.mismatches += 1
                if outcome.mismatches <= 3 {
                    Issue.record("\(problem): seed \(seed) #\(sequence) runLoop \(runLoop) 처음 \(original.debugDescription) \(log.joined(separator: ", "))")
                }
            }
            h.window.contentView = nil
        }
        return outcome
    }

    private func check(seed: UInt64, runLoop: Bool, onlyEdges: Bool, defaultSequences: Int) async throws {
        let environment = ProcessInfo.processInfo.environment
        let sequences = environment["OUTSIDE_FUZZ_SEQUENCES"].flatMap(Int.init) ?? defaultSequences
        let base = environment["OUTSIDE_FUZZ_SEED"].flatMap(UInt64.init) ?? 0
        let outcome = try await run(seed: base &+ seed, sequences: sequences, steps: 40, runLoop: runLoop, onlyEdges: onlyEdges)
        #expect(outcome.mismatches == 0)
        if environment["OUTSIDE_FUZZ_SEQUENCES"] != nil {
            print("OUTSIDE_FUZZ seed \(base &+ seed) runLoop \(runLoop) onlyEdges \(onlyEdges): \(outcome.sequences) sequences, "
                + "\(outcome.mismatches) mismatches, \(outcome.dropped) with dropped history, \(outcome.exact) checked exactly")
        }
    }

    /// 끝에 붙이거나 맨 앞에 붙이는 변경만: 기록을 버리지 않고 모두 되돌린 글이 꼭 맞는다.
    @Test(arguments: [201, 202] as [UInt64], [false, true])
    func appendsAndPrependsNeverDisturbTheHistory(seed: UInt64, runLoop: Bool) async throws {
        try await check(seed: seed, runLoop: runLoop, onlyEdges: true, defaultSequences: 12)
    }

    /// 아무 자리의 글자와 줄, 줄 지우기, 통째로 바꾸기까지: 겹치면 기록을 버릴 뿐 글이 엉뚱한 자리에 놓이지 않는다.
    @Test(arguments: [211, 212] as [UInt64], [false, true])
    func arbitraryOutsideChangesDegradeSafely(seed: UInt64, runLoop: Bool) async throws {
        try await check(seed: seed, runLoop: runLoop, onlyEdges: false, defaultSequences: 12)
    }
}
