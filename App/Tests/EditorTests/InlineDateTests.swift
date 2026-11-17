import AppKit
import Testing
import DateTime
import Models
@testable import Editor

@MainActor @Suite struct InlineDateTests {
    private func setup(_ source: String) throws -> (EditorHarness, Effects) {
        let h = try EditorHarness(source)
        let effects = Effects()
        h.editor.onAcceptDate = { request in
            effects.requests.append(request); effects.count += 1
            return InlineDateEffect(undo: { effects.count -= 1 }, redo: { effects.count += 1 })
        }
        h.caret(at: source.utf16.count)
        h.controller.updateDateSuggestion()
        return (h, effects)
    }
    @Test func movingBetweenEqualProposalsMovesUnderlineAndAcceptanceTogether() throws {
        let source = "- [ ] 회의 내일\n- [ ] 식사 내일\n유지할 마지막 줄"
        let (h, effects) = try setup(source)
        h.caret(atEndOfLine: 0)
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestionLine == 0)
        let firstProposal = h.controller.dateSuggestion
        let edits = AttributeEdits(storage: try #require(h.view.textStorage))
        defer { edits.stop() }
        h.press(NSResponder.down)
        #expect(h.editor.selectedRange.location == h.document.lines[1].end)
        #expect(h.controller.dateSuggestion == firstProposal)
        #expect(h.controller.dateSuggestionLine == 1)
        #expect(try !isDateUnderlined(h, line: 0))
        #expect(try isDateUnderlined(h, line: 1))
        let untouched = h.document.lines[2].fullRange
        #expect(!edits.ranges.isEmpty)
        #expect(edits.ranges.allSatisfy { NSIntersectionRange($0, untouched).length == 0 })
        h.press(NSResponder.tab)
        #expect(h.editor.text == "- [ ] 회의 내일\n- [ ] 식사\n유지할 마지막 줄")
        #expect(effects.requests.last?.source.line == 1)
        h.undo()
        #expect(h.editor.text == source)
        #expect(effects.count == 0)
    }

    @Test func distantSuggestionChangesInvalidateOnlyTheTwoLines() throws {
        let source = "회의 내일\n가운데 보존\n마지막 내일"
        let (h, _) = try setup(source)
        h.caret(atEndOfLine: 0)
        let edits = AttributeEdits(storage: try #require(h.view.textStorage))
        defer { edits.stop() }
        h.caret(atEndOfLine: 2)
        #expect(try !isDateUnderlined(h, line: 0))
        #expect(try isDateUnderlined(h, line: 2))
        #expect(!edits.ranges.isEmpty)
        #expect(edits.ranges.allSatisfy { NSIntersectionRange($0, h.document.lines[1].fullRange).length == 0 })
        #expect(h.editor.text == source)
    }

    @Test func lineInsertionClearsThePreviousUnderlineAndUndoKeepsSource() throws {
        let source = "회의 내일\n아래 글"
        let (h, _) = try setup(source)
        h.caret(atEndOfLine: 0)
        h.type("\n")
        #expect(h.controller.dateSuggestion == nil)
        #expect(try !isDateUnderlined(h, line: 0))
        #expect(h.editor.text == "회의 내일\n\n아래 글")
        h.undo()
        #expect(h.editor.text == source)
    }

    @Test(arguments: ["내일\n다음 줄", "윗줄 보존\n아주 긴 회의 제목 내일 오후 3시~4시\n아랫줄 보존",
                      "윗줄\n내일 뒤에도 글이 남습니다\n아랫줄"])
    func previewNeverOverlapsAnyText(source: String) throws {
        let (h, _) = try setup(source)
        let caret = source.contains("3시~4시") ? (source as NSString).range(of: "4시").upperBound
            : (source as NSString).range(of: "내일").upperBound
        h.caret(at: caret)
        h.controller.updateDateSuggestion()
        h.controller.layoutManager.ensureLayout(for: h.controller.layoutManager.documentRange)
        h.controller.layoutDateHint()
        #expect(!h.controller.dateHint.isHidden)
        let preview = h.controller.dateHint.frame
        let origin = h.view.textContainerOrigin
        h.controller.layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                let text = line.typographicBounds.offsetBy(dx: origin.x + fragment.layoutFragmentFrame.minX,
                                                          dy: origin.y + fragment.layoutFragmentFrame.minY)
                #expect(!preview.intersects(text), "preview \(preview) intersects text \(text)")
            }
            return true
        }
        #expect(h.editor.text == source)
    }

    private func isDateUnderlined(_ h: EditorHarness, line: Int) throws -> Bool {
        let display = try h.display(line: line)
        let range = (display.string as NSString).range(of: "내일")
        return (display.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
    }

    @MainActor private final class AttributeEdits {
        var ranges: [NSRange] = []
        var observer: NSObjectProtocol?
        weak var storage: NSTextStorage?
        init(storage: NSTextStorage) {
            self.storage = storage
            observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                object: storage, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let storage = self?.storage, storage.editedMask == .editedAttributes else { return }
                    self?.ranges.append(storage.editedRange)
                }
            }
        }
        func stop() { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    @Test(arguments: [
        ("회의 내일 3시", "회의"),
        ("간격  유지 `a  b` 회의 내일 3시", "간격  유지 `a  b` 회의"),
        ("회의 내일 3시~4시", "회의"),
        ("[ ] 회의 내일 3시", "[ ] 회의"),
        ("- [x] 회의 내일 3시", "- [x] 회의"),
        ("- 부모\n\t[ ] 회의 내일 3시", "- 부모\n\t[ ] 회의"),
        ("😀 내일 회의 3시", "😀 회의"),
        ("내일 회의 3시", "회의"),
        ("내일", ""),
        ("# 회의 내일 3시", "# 회의"),
        ("회의 내일 ３시", "회의"),
        ("회의 내일 3시".decomposedStringWithCanonicalMapping, "회의".decomposedStringWithCanonicalMapping)
    ])
    func acceptUndoRedoPreservesExactSource(pair: (String, String)) throws {
        let (h, effects) = try setup(pair.0)
        #expect(h.controller.dateSuggestion != nil)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.editor.text == pair.1)
        #expect(effects.count == 1)
        #expect(h.beeps == 0)
        h.undo()
        #expect(h.editor.text == pair.0)
        #expect(effects.count == 0)
        h.redo()
        #expect(h.editor.text == pair.1)
        #expect(effects.count == 1)
    }
    @Test(arguments: ["**회의 내일 3시**", "**내일 3시**", "[내일 3시](https://example.com)", "==내일 3시=={2}"])
    func hiddenMarkersSurviveAcceptanceAndUndo(source: String) throws {
        let (h, effects) = try setup(source)
        let end = (source as NSString).range(of: "3시").upperBound
        h.caret(at: end)
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestion != nil)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(effects.count == 1)
        #expect(!h.editor.text.contains("내일"))
        #expect(!h.editor.text.contains("****"))
        h.undo()
        #expect(h.editor.text == source)
        #expect(effects.count == 0)
    }
    @Test(arguments: ["`내일 3시`", "```\n내일 3시\n```", "[링크](https://x/내일3시)", "https://x/내일3시", "내일배움카드", "어제 3시", "회의 내일 3시 추가"])
    func excludedContextsAndContinuedTypingNeverOffer(source: String) throws {
        let (h, effects) = try setup(source)
        if let range = source.range(of: "3시") { h.caret(at: source[..<range.upperBound].utf16.count) }
        if source.hasSuffix("추가") { h.caret(at: source.utf16.count) }
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestion == nil)
        #expect(h.editor.text == source)
        #expect(effects.requests.isEmpty)
    }
    @Test func escapeThenTabIndentsAndMovementDismisses() throws {
        let source = "- 부모\n- 회의 내일 3시"
        let (h, effects) = try setup(source)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.controller.dateSuggestion == nil)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.editor.text == "- 부모\n\t- 회의 내일 3시")
        #expect(effects.count == 0)
        h.caret(at: 1)
        #expect(h.controller.dateSuggestion == nil)
    }
    @Test func markedTextDoesNotAcceptAndCommitOffers() throws {
        let (h, effects) = try setup("회의 내일 3")
        h.mark("시")
        #expect(h.controller.dateSuggestion == nil)
        let before = h.editor.text
        #expect(!h.controller.acceptDateSuggestion())
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.editor.text == before)
        #expect(h.view.hasMarkedText())
        h.commit("시")
        #expect(h.controller.dateSuggestion != nil)
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(effects.count == 1)
        h.undo()
        #expect(h.editor.text == "회의 내일 3시")
    }
    @Test func failedSaveLeavesSourceAndUndoUntouched() throws {
        let (h, _) = try setup("회의 내일 3시")
        h.editor.onAcceptDate = { _ in throw CocoaError(.fileWriteNoPermission) }
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.editor.text == "회의 내일 3시")
        #expect(!h.editor.undoManager.canUndo)
        #expect(h.beeps == 1)
    }
    @Test func acceptUndoOutsideFuzz() throws {
        // 고정 씨앗으로 날짜 종류/서식/바깥 덧붙임/입력/undo·redo의 순서를 섞는다.
        var seed: UInt64 = 0xDA7E
        for _ in 0..<120 {
            seed = seed &* 6364136223846793005 &+ 1
            let expression = ["내일 3시", "모레", "내일 3시~4시"][Int(seed % 3)]
            let prefix = ["😀 메모 ", "[ ] 일 ", "- 부모\n\t[ ] 할 일 "][Int((seed >> 8) % 3)]
            let source = prefix + expression
            let (h, effects) = try setup(source)
            h.press(#selector(NSResponder.insertTab(_:)))
            let accepted = h.editor.text
            h.editor.applyOutsideChange(to: accepted + "\n바깥에서 온 글")
            if seed & 1 == 0 {
                h.caret(at: h.editor.text.utf16.count)
                h.type("!"); h.undo()
            }
            h.undo()
            #expect(h.editor.text == source + "\n바깥에서 온 글")
            #expect(effects.count == 0)
            h.redo()
            #expect(h.editor.text == accepted + "\n바깥에서 온 글")
            #expect(effects.count == 1)
            #expect(h.replayMismatches.isEmpty)
        }
    }
    private final class Effects {
        var count = 0
        var requests: [InlineDateAcceptance] = []
    }
}
