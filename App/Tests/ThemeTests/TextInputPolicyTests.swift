import AppKit
import Testing
@testable import Theme

@MainActor @Suite struct TextInputPolicyTests {
    @Test func compositionSurvivesWithoutSystemDecorations() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        view.isRichText = false
        TextInputPolicy.apply(to: view)
        view.setMarkedText(NSAttributedString(string: "한", attributes: [.underlineStyle: 1, .underlineColor: NSColor.systemBlue]), selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.string == "한")
        #expect((view.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
        #expect(view.textStorage?.attribute(.underlineColor, at: 0, effectiveRange: nil) == nil)
        #expect((view.markedTextAttributes?[.underlineStyle] as? Int) == 0)
        #expect(!view.isAutomaticQuoteSubstitutionEnabled)
        #expect(!view.isAutomaticDashSubstitutionEnabled)
        #expect(!view.isAutomaticTextReplacementEnabled)
        #expect(!view.isAutomaticSpellingCorrectionEnabled)
        #expect(!view.isContinuousSpellCheckingEnabled)
        #expect(!view.isGrammarCheckingEnabled)
        #expect(!view.isAutomaticLinkDetectionEnabled)
        #expect(!view.isAutomaticDataDetectionEnabled)
        #expect(!view.isAutomaticTextCompletionEnabled)
        #expect(view.inlinePredictionType == .no)
        #expect(view.mathExpressionCompletionType == .no)
        view.insertText("한글", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.string == "한글")
    }

    @Test func reusedFieldEditorReceivesThePolicy() throws {
        let cell = PlainTextInputCell(textCell: "")
        let editor = NSTextView(frame: .zero)
        for _ in 0..<2 {
            editor.isAutomaticQuoteSubstitutionEnabled = true
            editor.isAutomaticSpellingCorrectionEnabled = true
            editor.inlinePredictionType = .yes
            #expect(cell.setUpFieldEditorAttributes(editor) === editor)
            #expect(!editor.isAutomaticQuoteSubstitutionEnabled)
            #expect(!editor.isAutomaticSpellingCorrectionEnabled)
            #expect(editor.inlinePredictionType == .no)
        }
    }
}
