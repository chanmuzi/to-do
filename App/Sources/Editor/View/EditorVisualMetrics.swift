import AppKit
import Theme

/// 기존 장식 치수를 tokens.json에서 읽는다. 원문 파싱과 선택 계산 정밀도는 포함하지 않는다.
nonisolated struct EditorVisualMetrics {
    let glyphStroke: CGFloat
    let checkmarkSize: CGFloat
    let checkmarkStroke: CGFloat
    let bracketGutter: CGFloat
    let bulletDot: CGFloat
    let bulletSquare: CGFloat
    let bulletInset: CGFloat
    let chevronSize: CGFloat
    let chevronStroke: CGFloat
    let countGap: CGFloat
    let guideOffset: CGFloat
    let highlightPadX: CGFloat
    let highlightPadY: CGFloat
    let linkFieldGap: CGFloat
    let linkFieldPadX: CGFloat
    let copyButtonInset: CGFloat
    let heading1Before: CGFloat
    let heading1After: CGFloat
    let heading2Before: CGFloat
    let heading2After: CGFloat
    let heading3Before: CGFloat
    let heading3After: CGFloat

    var headingSpacing: [(before: CGFloat, after: CGFloat)] {
        [(heading1Before, heading1After), (heading2Before, heading2After), (heading3Before, heading3After)]
    }

    @MainActor init(theme: Theme) {
        glyphStroke = theme.component(.editorGlyphStroke)
        checkmarkSize = theme.component(.editorCheckmarkSize)
        checkmarkStroke = theme.component(.editorCheckmarkStroke)
        bracketGutter = theme.component(.editorBracketGutter)
        bulletDot = theme.component(.editorBulletDot)
        bulletSquare = theme.component(.editorBulletSquare)
        bulletInset = theme.component(.editorBulletInset)
        chevronSize = theme.component(.editorChevronSize)
        chevronStroke = theme.component(.editorChevronStroke)
        countGap = theme.component(.editorCountGap)
        guideOffset = theme.component(.editorGuideOffset)
        highlightPadX = theme.component(.editorHighlightPadX)
        highlightPadY = theme.component(.editorHighlightPadY)
        linkFieldGap = theme.component(.editorLinkFieldGap)
        linkFieldPadX = theme.component(.editorLinkFieldPadX)
        copyButtonInset = theme.component(.editorCopyButtonInset)
        heading1Before = theme.component(.editorHeading1Before)
        heading1After = theme.component(.editorHeading1After)
        heading2Before = theme.component(.editorHeading2Before)
        heading2After = theme.component(.editorHeading2After)
        heading3Before = theme.component(.editorHeading3Before)
        heading3After = theme.component(.editorHeading3After)
    }
}
