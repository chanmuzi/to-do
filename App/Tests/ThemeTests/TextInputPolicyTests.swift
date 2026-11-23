import AppKit
import Testing
@testable import Theme

@MainActor @Suite struct TextInputPolicyTests {
    @Test func compositionSurvivesWithoutSystemDecorations() throws {
        let view = PlainTextInputView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        view.isRichText = false
        TextInputPolicy.apply(to: view)
        view.setMarkedText(NSAttributedString(string: "한", attributes: [.underlineStyle: 1, .underlineColor: NSColor.systemBlue]), selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.string == "한")
        #expect((view.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
        #expect(view.textStorage?.attribute(.underlineColor, at: 0, effectiveRange: nil) == nil)
        #expect(view.markedTextAttributes?[.underlineStyle] == nil)
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

    /// 저장소와 임시 속성에 없는 조합 표시도 AppKit이 그리므로 실제 비트맵을 비교한다.
    @Test(arguments: [false, true])
    func inputMethodUnderlineUsesTheConfiguredStyle(underline: Bool) throws {
        let theme = try Theme.bundled(appearance: .light)
        let field = CommandInputField(theme: theme)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 32),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = field
        window.makeFirstResponder(field)
        let view = try #require(field.currentEditor() as? NSTextView)
        TextInputPolicy.applyNoteStyle(to: view, theme: theme, underline: underline)
        func render() throws -> Data {
            window.displayIfNeeded()
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            let bytes = try #require(image.bitmapData)
            return Data(bytes: bytes, count: image.bytesPerRow * image.pixelsHigh)
        }
        func markAndRender(_ input: Any) throws -> Data {
            view.setMarkedText(input, selectedRange: NSRange(location: 1, length: 0),
                               replacementRange: view.hasMarkedText() ? view.markedRange() : view.selectedRange())
            return try render()
        }
        let ordinary = try markAndRender("한")
        let input = NSAttributedString(string: "한", attributes: [.markedClauseSegment: 0,
            .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: NSColor.systemBlue])
        let decorated = try markAndRender(input)
        #expect(ordinary == decorated)
        #expect(view.markedRange() == NSRange(location: 0, length: 1))
        view.insertText("한", replacementRange: view.markedRange())
        #expect(!view.hasMarkedText() && view.string == "한")
        let committed = try render()
        #expect((decorated != committed) == underline)
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
