import AppKit
import Synchronization
import Testing
@testable import Editor

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FLOAT_EDITOR_PERF"] == "1"))
struct EditorPerformanceTests {
    private struct Counts {
        var parses = 0
        var fullParses = 0
        var layouts = 0
        var phases: [String: Duration] = [:]
    }

    private struct Sample {
        let elapsed: Double
        let counts: Counts
    }

    private func milliseconds(_ value: Duration) -> Double {
        let parts = value.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private func measure(documentLength: Int, _ action: () -> Void) -> Sample {
        let counts = Mutex(Counts())
        let elapsed = MarkdownDocument.$observeParse.withValue({ length in
            counts.withLock {
                $0.parses += 1
                if length >= documentLength / 2 { $0.fullParses += 1 }
            }
        }) {
            EditorTrace.$observe.withValue({ name, duration in
                let key = name.description
                counts.withLock {
                    if key == "ensureLayout" { $0.layouts += 1 }
                    $0.phases[key, default: .zero] += duration
                }
            }) {
                ContinuousClock().measure(action)
            }
        }
        return Sample(elapsed: milliseconds(elapsed), counts: counts.withLock { $0 })
    }

    private func fixture(rows: Int) -> String {
        let prefix = ["# 계획", "오늘 **검토** 항목", "- 첫 항목", "[ ] 확인", "다음 항목", "+ 작업"]
        let children = (0..<20).map { "\t자식 \($0)" }
        let pattern = ["## 회의", "- 안건", "[ ] 확인", "+ 자료", "\t참고", "**강조** 표시", "메모 <!-- 파랑 바탕 -->"]
        return (prefix + children + (0..<(rows - prefix.count - children.count)).map { pattern[$0 % pattern.count] })
            .joined(separator: "\n")
    }

    @Test(arguments: [200, 2_000, 10_000])
    func editorActions(rows: Int) throws {
        let source = fixture(rows: rows)
        let h = try EditorHarness(source)
        defer { h.window.close() }
        let editor = h.controller
        editor.foldAnimationsEnabled = { false }
        let length = h.document.length
        #expect(editor.textContainer.size.width > 0)
        #expect(h.document.lines.count == rows)
        #expect(h.document.lines[5].subtreeEnd == 26)
        var results: [String: [Sample]] = [:]
        for _ in 0..<20 {
            autoreleasepool {
                let row = h.document.lines[1]
                h.place(at: row.contentStart, length: 2)
                results["highlight", default: []].append(measure(documentLength: length) { h.perform(.highlight) })
                #expect(h.document.lines[1].markedSpans.count == 2)
                h.undo()

                editor.showBlocks(BlockSelection(anchor: 2, focus: 4))
                results["blocks", default: []].append(measure(documentLength: length) { h.perform(.highlight) })
                #expect((2...4).allSatisfy { h.document.blockColor(at: $0) != nil })
                h.undo()
                editor.clearBlocks()

                for (name, closed) in [("fold", true), ("unfold", false)] {
                    results[name, default: []].append(measure(documentLength: length) { editor.toggleFold(line: 5) })
                    #expect(editor.folded.contains(5) == closed)
                    #expect(editor.currentKeys()[25].isCollapsed == closed)
                }

                h.caret(atEndOfLine: 1)
                results["type", default: []].append(measure(documentLength: length) { h.type("가") })
                #expect(h.document.length == length + 1)
                h.undo()
                #expect(h.editor.text == source)
            }
        }
        for name in results.keys.sorted() {
            let samples = results[name]!
            let times = samples.map(\.elapsed).sorted()
            let median = (times[9] + times[10]) / 2
            let phases = ["didProcessEditing.parse", "LinePresentation.keys", "measureContentHeight", "textParagraphWith"].map { key in
                let values = samples.map { milliseconds($0.counts.phases[key, default: .zero]) }.sorted()
                return String(format: "%.3f", (values[9] + values[10]) / 2)
            }.joined(separator: ",")
            func range(_ field: KeyPath<Counts, Int>) -> String {
                let values = samples.map { $0.counts[keyPath: field] }
                return "\(values.min()!)-\(values.max()!)"
            }
            print("PERF \(rows) \(name) " + String(format: "%.3f %.3f", median, times[19])
                  + " parses=\(range(\.parses)) full=\(range(\.fullParses)) layout=\(range(\.layouts)) phases=\(phases)")
            #if DEBUG
            #expect(median < 500)
            #else
            #expect(median < 100)
            #endif
        }
    }
}
