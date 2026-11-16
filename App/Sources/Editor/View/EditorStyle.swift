import AppKit
import Theme

/// 토큰에 없는 편집기 치수. spec 6장의 표와 시안의 본문 규칙에 적힌 값을 한곳에 모았다.
nonisolated enum EditorMetrics {
    /// 체크박스 테두리, 빈 원 글머리표의 선 굵기.
    static let glyphStroke: CGFloat = 1.25
    /// 체크 표시 그림의 크기와 선 굵기.
    static let checkmarkSize: CGFloat = 9
    static let checkmarkStroke: CGFloat = 1
    /// 대괄호 체크박스일 때의 왼쪽 칸 너비.
    static let bracketGutter: CGFloat = 28
    /// 글머리표: 원 지름, 사각 한 변, 칸 안에서의 왼쪽 여백.
    static let bulletDot: CGFloat = 5
    static let bulletSquare: CGFloat = 4
    static let bulletInset: CGFloat = 4
    /// 토글 꺾쇠의 크기와 선 굵기, 줄 수 앞의 간격.
    static let chevronSize: CGFloat = 12
    static let chevronStroke: CGFloat = 0.875
    static let countGap: CGFloat = 8
    /// 안내선이 놓이는 곳(부모 글머리 중심).
    static let guideOffset: CGFloat = 6
    /// 형광펜 좌우와 위아래 여백.
    static let highlightPadX: CGFloat = 2
    static let highlightPadY: CGFloat = 1
    /// 인라인 코드 좌우 여백, 바깥 간격, 위아래 여백.
    static let inlineCodePadX: CGFloat = 4
    static let inlineCodeMargin: CGFloat = 1
    static let inlineCodePadY: CGFloat = 1
    /// 코드 블록 안쪽 여백(위아래 7, 좌우 10), 위아래 바깥 간격, 줄 높이.
    static let codeBlockPadY: CGFloat = 7
    static let codeBlockPadX: CGFloat = 10
    static let codeBlockMargin: CGFloat = 4
    static let codeLineHeight: CGFloat = 18
    /// 코드 블록 복사 버튼과 블록 모서리 사이.
    static let copyButtonInset: CGFloat = 4
    static let copyIconSize: CGFloat = 13
    /// 제목 위아래 여백(1, 2, 3).
    static let headingSpacing: [(before: CGFloat, after: CGFloat)] = [(4, 4), (6, 2), (6, 0)]
    /// 감춘 글자의 크기. 자리를 거의 차지하지 않게 한다.
    static let hiddenFontSize: CGFloat = 0.01
    /// 접힌 줄의 높이.
    static let collapsedLineHeight: CGFloat = 0.01
}

/// 테마에서 풀어 온 편집기의 글꼴, 색, 치수. 테마나 설정이 바뀌면 다시 만든다.
nonisolated struct EditorStyle {
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
    let codeBackground: NSColor
    let codeLine: NSColor
    let codeForeground: NSColor
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

    @MainActor
    init(theme: Theme, configuration: MarkdownEditorConfiguration, increaseContrast: Bool) {
        func color(_ token: ColorToken) -> NSColor { theme.rgba(token).nsColor }
        body = TextFont(theme.nsFont(.body), lineHeight: theme.lineHeight(.body))
        strong = theme.nsFont(.strong)
        headings = [TextStyle.h1, .h2, .h3].map { TextFont(theme.nsFont($0), lineHeight: theme.lineHeight($0)) }
        headingTracking = [TextStyle.h1, .h2, .h3].map { theme.tracking($0) }
        inlineCode = theme.nsFont(.code)
        codeBlock = TextFont(theme.nsFont(.code), lineHeight: EditorMetrics.codeLineHeight)
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
        codeBackground = color(.codeBackground)
        codeLine = color(.codeLine)
        codeForeground = color(.codeForeground)
        highlightBackgrounds = HighlightColor.allCases.map { color($0.background) }
        highlightForegrounds = HighlightColor.allCases.map { color($0.foreground) }

        checkboxStyle = configuration.checkboxStyle
        gutter = checkboxStyle == .bracket ? EditorMetrics.bracketGutter : theme.component(.gutter)
        indent = theme.component(.indent)
        checkSize = theme.component(.checkSize)
        checkRadius = theme.shape(.checkRadius)
        highlightRadius = theme.shape(.highlightRadius)
        codeRadius = theme.shape(.codeRadius)
        codeBlockRadius = theme.shape(.codeBlockRadius)
        borderWidth = theme.shape(.borderWidth)
    }

    func heading(_ level: Int) -> TextFont { headings[min(max(level, 1), 3) - 1] }
    func highlightBackground(_ number: Int) -> NSColor { highlightBackgrounds[min(max(number, 1), 4) - 1] }
    func highlightForeground(_ number: Int) -> NSColor { highlightForegrounds[min(max(number, 1), 4) - 1] }
}
