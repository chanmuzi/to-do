#if DEBUG
import AppKit

/// 시스템 이벤트나 클립보드를 쓰지 않고, 이 프로세스의 입력 칸만 조사한다.
enum DebugInputVerification {
    static func state(of view: NSTextView) -> [String: Any] {
        var selectionColor = ""
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let native = view.selectedTextAttributes[.backgroundColor] as? NSColor,
               let srgb = native.usingColorSpace(.sRGB) {
                selectionColor = String(format: "#%02X%02X%02X",
                                        Int(round(srgb.redComponent * 255)), Int(round(srgb.greenComponent * 255)),
                                        Int(round(srgb.blueComponent * 255)))
            }
        }
        return [
            "text": view.string,
            "selection": NSStringFromRange(view.selectedRange()),
            "markedRange": NSStringFromRange(view.markedRange()),
            "hasMarkedText": view.hasMarkedText(),
            "selectionColor": selectionColor,
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
