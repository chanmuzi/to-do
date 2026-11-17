import AppKit

/// 사람이 친 글을 그대로 받는 입력 칸의 공통 정책. 조합은 유지하고 시스템의 장식과 자동 변경만 끈다.
@MainActor
public enum TextInputPolicy {
    public static func apply(to view: NSTextView) {
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.inlinePredictionType = .no
        view.mathExpressionCompletionType = .no
        view.smartInsertDeleteEnabled = false
        // 밑줄을 그리지 않는다. marked range와 입력기의 조합·후보 선택 자체는 건드리지 않는다.
        view.markedTextAttributes = [.underlineStyle: 0]
    }
}

/// 창이 재사용하는 필드 편집기에 매번 정책을 적용한다. 다른 입력 칸의 시스템 설정이 넘어오지 않는다.
@MainActor
public final class PlainTextInputCell: NSTextFieldCell {
    public override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let view = editor as? NSTextView { TextInputPolicy.apply(to: view) }
        return editor
    }
}
