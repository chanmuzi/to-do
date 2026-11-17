import AppKit
import Testing
import DateTime
@testable import Editor

@MainActor @Suite struct DateFeedbackTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func now(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour))!
    }

    @Test(arguments: ["오늘 오후 1시 미팅", "회의 내일 오후 3시"], [false, true])
    func feedbackInputPaths(source: String, composing: Bool) throws {
        let h = try EditorHarness()
        h.controller.dateNow = { now(10) }
        h.controller.dateCalendar = calendar
        h.editor.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        for character in source {
            if composing && character.isLetter {
                h.mark(String(character))
                #expect(h.controller.dateSuggestion == nil)
                h.commit(String(character))
            } else { h.type(String(character)) }
        }
        #expect(h.editor.text == source)
        #expect(h.controller.dateSuggestion != nil)
        let expression = try #require(DateTimeParser.firstExpression(in: source, now: now(10), calendar: calendar))
        #expect(calendar.component(.day, from: expression.start) == (source.hasPrefix("회의") ? 19 : 18))
        #expect(expression.ranges.map { (source as NSString).substring(with: $0) } ==
                [source.hasPrefix("회의") ? "내일 오후 3시" : "오늘 오후 1시"])
    }

    @Test func explicitPastAndBareClock() throws {
        #expect(InlineDateProposal.find(in: "오늘 오후 1시", caret: "오늘 오후 1시".utf16.count, now: now(14), calendar: calendar) == nil)
        let source = "오후 1시"
        let proposal = try #require(InlineDateProposal.find(in: source, caret: source.utf16.count, now: now(14), calendar: calendar))
        #expect(calendar.component(.day, from: proposal.item.start) == 19)
    }

    @Test func inactiveEditorDoesNotOfferUntilFocused() throws {
        let h = try EditorHarness("회의 내일 오후 3시")
        h.editor.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        h.caret(at: h.editor.text.utf16.count)
        h.controller.forcesActiveAppearance = false
        h.controller.updateDateSuggestion()
        #expect(h.controller.dateSuggestion == nil)
        h.controller.forcesActiveAppearance = true
        h.controller.focusDidChange()
        #expect(h.controller.dateSuggestion != nil)
    }

    @Test(arguments: [0, 1, 3, 7, 11])
    func anyCaretOnLineAcceptsAndRestoresExactSource(position: Int) throws {
        let source = "회의 내일 오후 3시 메모"
        let h = try EditorHarness(source)
        var count = 0
        h.editor.onAcceptDate = { _ in
            count += 1
            return InlineDateEffect(undo: { count -= 1 }, redo: { count += 1 })
        }
        h.caret(at: position)
        #expect(h.controller.dateSuggestion != nil)
        h.press(NSResponder.tab)
        #expect(h.editor.text == "회의 메모")
        #expect(count == 1)
        h.undo()
        #expect(h.editor.text == source)
        #expect(h.editor.selectedRange.location == position)
        #expect(count == 0)
        h.redo()
        #expect(h.editor.text == "회의 메모")
        #expect(count == 1)
    }

    @Test func dismissalSurvivesMovementFocusAndOtherLineEdits() throws {
        let h = try EditorHarness("회의 내일 오후 3시\n다른 줄")
        h.editor.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        h.caret(at: 1)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.caret(at: 0)
        #expect(h.controller.dateSuggestion == nil)
        h.caret(at: h.editor.text.utf16.count)
        h.type("!")
        h.caret(at: 2)
        h.controller.focusDidChange()
        #expect(h.controller.dateSuggestion == nil)
        h.type("!")
        #expect(h.controller.dateSuggestion != nil)
        #expect(h.editor.text == "회의! 내일 오후 3시\n다른 줄!")
    }

    @Test func unmarkWithoutInsertAlsoRefreshes() throws {
        let h = try EditorHarness("회의 내일 오후 3")
        h.editor.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        h.caret(at: h.editor.text.utf16.count)
        h.mark("시")
        #expect(h.controller.dateSuggestion == nil)
        h.step { h.view.unmarkText() }
        #expect(h.controller.dateSuggestion != nil)
        #expect(h.editor.text == "회의 내일 오후 3시")
    }

    @Test func escapeFollowsTheUnchangedLineWhenLinesAreInsertedAbove() throws {
        let source = "윗줄\n회의 내일 오후 3시\n아랫줄"
        let h = try EditorHarness(source)
        h.editor.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        h.caret(at: 4)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.caret(at: 0)
        h.type("추가\n")
        h.caret(at: 7)
        #expect(h.controller.dateSuggestion == nil)
        h.editor.applyOutsideChange(to: "바깥 줄\n" + h.editor.text)
        h.caret(at: 12)
        #expect(h.controller.dateSuggestion == nil)
        #expect(h.editor.text == "바깥 줄\n추가\n" + source)
        h.type("!")
        #expect(h.controller.dateSuggestion != nil)
    }

    @Test func firstExpressionWinsEvenWithCaretAtSecond() throws {
        let source = "내일 오후 3시 회의 모레 오후 4시 식사"
        let proposal = try #require(InlineDateProposal.find(in: source, caret: source.utf16.count, now: now(10), calendar: calendar))
        #expect(proposal.expression.ranges.map { (source as NSString).substring(with: $0) } == ["내일 오후 3시"])
        #expect(InlineDateProposal.find(in: "오늘 오후 1시 회의 내일 오후 4시 식사", caret: 0, now: now(14), calendar: calendar) == nil)
    }
}
