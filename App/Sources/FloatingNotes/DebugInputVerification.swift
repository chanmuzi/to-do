#if DEBUG
import AppKit

/// 시스템 이벤트나 클립보드를 쓰지 않고, 이 프로세스의 입력 칸만 조사한다.
enum DebugInputVerification {
    static func descendant(in view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        if predicate(view) { return view }
        for child in view.subviews {
            if let result = descendant(in: child, matching: predicate) { return result }
        }
        return nil
    }

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
        var drawn: [String] = []
        let range = view.markedRange()
        if view.hasMarkedText(), let layout = view.textLayoutManager, let storage = layout.textContentManager,
           let start = storage.location(storage.documentRange.location, offsetBy: range.location) {
            layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, _ in
                drawn.append(String(describing: attributes))
                return false
            }
        } else if view.hasMarkedText(), let layout = view.layoutManager {
            drawn.append(String(describing: layout.temporaryAttributes(atCharacterIndex: range.location, effectiveRange: nil)))
        }
        return [
            "rendered": drawn,
            "stored": view.hasMarkedText() ? String(describing: view.textStorage?.attributes(at: range.location, effectiveRange: nil)) : "",
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
}
#endif
