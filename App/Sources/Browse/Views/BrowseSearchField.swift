import AppKit
import Theme

/// 검색 칸(spec 8): 높이 26, `surface-2` 바탕과 `line` 테두리, 12pt 돋보기, 자리 글자 "노트 찾기".
final class BrowseSearchField: NSView {
    static let placeholder = "노트 찾기"

    private let style: BrowseStyle
    private let iconView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: BrowseSearchField.placeholder)
    private let scrollView = NSScrollView()
    let textView: BrowseTextView

    init(style: BrowseStyle) {
        self.style = style
        textView = Self.makeTextView()
        super.init(frame: .zero)
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        iconView.imageScaling = .scaleNone
        iconView.setAccessibilityElement(false)
        placeholderLabel.wantsLayer = true
        placeholderLabel.setAccessibilityElement(false)
        [iconView, placeholderLabel, scrollView].forEach(addSubview)
        textView.setAccessibilityLabel(Self.placeholder)
        textView.setAccessibilityPlaceholderValue(Self.placeholder)
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 한 줄짜리 텍스트 뷰. 긴 글은 줄을 바꾸지 않고 옆으로 흐른다.
    private static func makeTextView() -> BrowseTextView {
        let view = BrowseTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.maximumNumberOfLines = 1
        view.textContainer?.lineBreakMode = .byClipping
        view.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        return view
    }

    /// 자리 글자는 칸이 비어 있을 때만 보인다. 나타날 때는 `dur` 동안(규칙 8), 글자를 치기 시작하면 바로 비킨다
    /// (흐려지는 동안 친 글자와 겹쳐 보이지 않게).
    func updatePlaceholder(animated: Bool) {
        let alpha: CGFloat = textView.string.isEmpty ? 1 : 0
        guard placeholderLabel.alphaValue != alpha else { return }
        guard animated, alpha == 1 else {
            placeholderLabel.alphaValue = alpha
            return
        }
        style.animate { placeholderLabel.animator().alphaValue = alpha }
    }

    var isPlaceholderVisible: Bool { placeholderLabel.alphaValue > 0 }

    func refreshTheme() {
        let theme = style.theme
        iconView.image = style.symbol("magnifyingglass", size: .iconSmall)
        iconView.contentTintColor = style.color(.text3)
        placeholderLabel.font = style.plainFont
        placeholderLabel.textColor = style.color(.text3)
        textView.font = style.plainFont
        textView.textColor = style.color(.text)
        textView.typingAttributes = [.font: style.plainFont, .foregroundColor: style.color(.text)]
        textView.insertionPointColor = style.color(.accent)
        textView.caretWidth = theme.component(.caretWidth)
        textView.selectedTextAttributes = [.backgroundColor: style.color(.hover)]
        needsLayout = true
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    /// 칸은 `surface-2` 바탕에 1px `line` 테두리다. 고른 줄(`hover`가 겹친 바탕)과 노트 찾기 바탕(`surface`)이
    /// 같은 회색으로 보이지 않게 테두리로 칸을 가른다(라이트와 다크 모두).
    override func updateLayer() {
        layer?.cornerRadius = style.theme.shape(.controlRadius)
        layer?.backgroundColor = style.cgColor(.surface2, in: self)
        layer?.borderWidth = style.theme.shape(.borderWidth)
        layer?.borderColor = style.cgColor(.line, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 칸의 빈 곳을 눌러도 글자 칸으로 커서가 간다.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let theme = style.theme
        let padding = style.rowPadding
        let icon = theme.component(.iconSmall)
        func centered(_ size: NSSize, x: CGFloat) -> NSRect {
            NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        }
        let slot = centered(NSSize(width: icon, height: icon), x: padding)
        iconView.frame = theme.symbolFrame(slot)

        let inputX = slot.maxX + theme.component(.browseGap)
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: style.plainFont).rounded(.up)
            ?? theme.lineHeight(.row)
        let inputFrame = centered(
            NSSize(width: max(0, bounds.width - padding - inputX), height: lineHeight), x: inputX
        )
        scrollView.frame = inputFrame
        textView.minSize = inputFrame.size
        if textView.frame.height != lineHeight || textView.frame.width < inputFrame.width {
            textView.frame.size = NSSize(width: max(textView.frame.width, inputFrame.width), height: lineHeight)
        }
        // 자리 글자는 입력한 글자가 놓일 자리에서 시작한다.
        placeholderLabel.frame = style.labelFrame(
            placeholderLabel, textX: inputX,
            textWidth: min(style.textWidth(of: placeholderLabel), inputFrame.width), centeredIn: bounds.height
        )
    }
}
