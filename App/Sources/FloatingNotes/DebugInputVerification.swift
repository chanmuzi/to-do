#if DEBUG
import AppKit

/// 시스템 이벤트나 클립보드를 쓰지 않고, 이 프로세스의 입력 칸만 조사한다.
enum DebugInputVerification {
    static func state(of view: NSTextView) -> [String: Any] {
        [
            "text": view.string,
            "markedRange": NSStringFromRange(view.markedRange()),
            "hasMarkedText": view.hasMarkedText(),
            "markedAttributes": String(describing: view.markedTextAttributes),
            "quotes": view.isAutomaticQuoteSubstitutionEnabled,
            "dashes": view.isAutomaticDashSubstitutionEnabled,
            "replacement": view.isAutomaticTextReplacementEnabled,
            "correction": view.isAutomaticSpellingCorrectionEnabled,
            "spelling": view.isContinuousSpellCheckingEnabled,
            "grammar": view.isGrammarCheckingEnabled,
            "links": view.isAutomaticLinkDetectionEnabled,
            "data": view.isAutomaticDataDetectionEnabled,
            "completion": view.isAutomaticTextCompletionEnabled,
            "prediction": view.inlinePredictionType.rawValue,
            "math": view.mathExpressionCompletionType.rawValue,
            "firstResponder": view.window?.firstResponder === view,
            "keyWindow": view.window?.isKeyWindow ?? false,
        ]
    }

    static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.accessibilityLabel() == "검색" { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }
}
#endif
