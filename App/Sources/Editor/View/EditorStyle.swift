import AppKit
import Theme

/// 화면에 표시하지 않는 글자와 접힌 줄을 TextKit에 남겨 두기 위한 계산 정밀도.
nonisolated enum EditorMetrics {
    static let hiddenFontSize: CGFloat = 0.01
    static let collapsedLineHeight: CGFloat = 0.01
}

/// 테마에서 풀어 온 편집기의 글꼴, 색, 치수. 테마나 설정이 바뀌면 다시 만든다.
nonisolated struct EditorStyle {
    let metrics: EditorVisualMetrics
    struct TextFont {
        let font: NSFont
        let lineHeight: CGFloat
        /// 글자 자체의 높이(바탕 상자의 높이를 정한다).
        let glyphHeight: CGFloat

        init(_ font: NSFont, lineHeight: CGFloat) {
            self.font = font
            self.lineHeight = lineHeight
            self.glyphHeight = ceil(font.ascender - font.descender)
        }
    }

    let bodyParagraph: NSParagraphStyle
    let body: TextFont
    let strong: NSFont
    let headings: [TextFont]
    let headingTracking: [CGFloat]
    let inlineCode: NSFont
    let codeBlock: TextFont
    let micro: NSFont
    let hidden: NSFont

    let text: NSColor
    let text2: NSColor
    let text3: NSColor
    let surface: NSColor
    let guide: NSColor
    let accent: NSColor
    let link: NSColor
    let line: NSColor
    let surface2: NSColor
    /// 인라인 코드 바탕, 코드 블록 바탕. 테두리는 없다.
    let codeBackground: NSColor
    let codeBlockBackground: NSColor
    /// 코드 블록 글자.
    let codeForeground: NSColor
    /// 인라인 코드 글자(설정에 따라 강조색 또는 `codeForeground`).
    let inlineCodeForeground: NSColor
    let highlightBackgrounds: [NSColor]
    let highlightForegrounds: [NSColor]

    let gutter: CGFloat
    let indent: CGFloat
    let checkSize: CGFloat
    let checkRadius: CGFloat
    let highlightRadius: CGFloat
    let codeRadius: CGFloat
    let codeBlockRadius: CGFloat
    let borderWidth: CGFloat
    let checkboxStyle: CheckboxStyle
    /// 인라인 코드 상자: 좌우 안쪽 여백, 바깥 간격, 높이, 줄 가운데에서 아래로 내리는 양, 글자 기준선을 올리는 양.
    let codePadX: CGFloat
    let codeGap: CGFloat
    let codeHeight: CGFloat
    let codeDrop: CGFloat
    let codeRise: CGFloat
    /// 코드 블록: 좌우와 위아래 안쪽 여백, 위아래 바깥 간격.
    let codeBlockPadX: CGFloat
    let codeBlockPadY: CGFloat
    let codeBlockGap: CGFloat
    /// 인용문: 왼쪽 막대의 너비, 블록 왼쪽 끝에서 글자까지.
    let quoteBarWidth: CGFloat
    let quotePadding: CGFloat

    @MainActor
    init(theme: Theme, configuration: MarkdownEditorConfiguration, increaseContrast: Bool) {
        metrics = EditorVisualMetrics(theme: theme)
        func color(_ token: ColorToken) -> NSColor { theme.rgba(token).nsColor }
        body = TextFont(theme.nsFont(.body), lineHeight: theme.lineHeight(.body))
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = body.lineHeight
        paragraph.maximumLineHeight = body.lineHeight
        bodyParagraph = paragraph
        strong = theme.nsFont(.strong)
        headings = [TextStyle.h1, .h2, .h3].map { TextFont(theme.nsFont($0), lineHeight: theme.lineHeight($0)) }
        headingTracking = [TextStyle.h1, .h2, .h3].map { theme.tracking($0) }
        inlineCode = theme.nsFont(.code)
        codeBlock = TextFont(theme.nsFont(.codeBlock), lineHeight: theme.lineHeight(.codeBlock))
        micro = theme.nsFont(.micro)
        hidden = NSFont.systemFont(ofSize: EditorMetrics.hiddenFontSize)

        text = color(.text)
        text2 = color(.text2)
        // 대비 증가가 켜져 있으면 흐린 글자를 한 단계 진하게 한다(spec 17).
        text3 = color(increaseContrast ? .text2 : .text3)
        surface = color(.surface)
        guide = color(.guide)
        accent = color(.accent)
        link = color(.link)
        line = color(.line)
        surface2 = color(.surface2)
        codeBackground = color(.codeBackground)
        codeBlockBackground = color(.codeBlockBackground)
        codeForeground = color(.codeForeground)
        inlineCodeForeground = color(configuration.inlineCodeStyle == .accent ? .codeAccent : .codeForeground)
        highlightBackgrounds = HighlightColor.allCases.map { color($0.background) }
        highlightForegrounds = HighlightColor.allCases.map { color($0.foreground) }

        checkboxStyle = configuration.checkboxStyle
        gutter = checkboxStyle == .bracket ? metrics.bracketGutter : theme.component(.gutter)
        indent = theme.component(.indent)
        checkSize = theme.component(.checkSize)
        checkRadius = theme.shape(.checkRadius)
        highlightRadius = theme.shape(.highlightRadius)
        codeRadius = theme.shape(.codeRadius)
        codeBlockRadius = theme.shape(.codeBlockRadius)
        borderWidth = theme.shape(.borderWidth)
        codePadX = theme.component(.codePaddingX)
        codeGap = theme.component(.codeGap)
        codeHeight = theme.component(.codeHeight)
        codeDrop = theme.component(.codeDrop)
        codeRise = theme.component(.codeRise)
        codeBlockPadX = theme.component(.codeBlockPaddingX)
        codeBlockPadY = theme.component(.codeBlockPaddingY)
        codeBlockGap = theme.component(.codeBlockGap)
        quoteBarWidth = theme.component(.quoteBarWidth)
        quotePadding = theme.component(.quotePadding)
    }

    /// 그 줄 글꼴에 맞춘 인라인 코드 글꼴. 제목 안에서는 제목 크기에 비례해 커진다.
    func inlineCode(in lineFont: TextFont) -> NSFont {
        let scale = lineFont.font.pointSize / body.font.pointSize
        return scale == 1 ? inlineCode : inlineCode.withSize((inlineCode.pointSize * scale * 2).rounded() / 2)
    }

    /// 그 줄에서의 인라인 코드 상자 높이.
    func codeHeight(in lineFont: TextFont) -> CGFloat {
        let scale = lineFont.font.pointSize / body.font.pointSize
        return min(lineFont.lineHeight, (codeHeight * scale).rounded())
    }

    func heading(_ level: Int) -> TextFont { headings[min(max(level, 1), 3) - 1] }
    func highlightBackground(_ number: Int) -> NSColor { highlightBackgrounds[min(max(number, 1), 4) - 1] }
    func highlightForeground(_ number: Int) -> NSColor { highlightForegrounds[min(max(number, 1), 4) - 1] }
}
