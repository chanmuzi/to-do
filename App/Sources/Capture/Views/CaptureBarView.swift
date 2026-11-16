import AppKit
import Theme

/// 캡처 바의 한 줄(spec 7, 화면 3): `>` / 입력 칸 / 스페이스 / 리마인더. 닫는 버튼은 없다.
final class CaptureBarView: NSView {
    private let style: CaptureStyle
    private let background: CaptureBackgroundView
    private let promptLabel = NSTextField(labelWithString: ">")
    private let placeholderLabel = NSTextField(labelWithString: CaptureBarView.placeholder)
    private let scrollView = NSScrollView()
    let textView: CaptureTextView
    private let spaceBadge: CaptureBadgeView
    private let reminderBadge: CaptureBadgeView
    private var underlinedRange: NSRange?

    static let placeholder = "메모나 할 일을 적으세요"

    init(style: CaptureStyle) {
        self.style = style
        background = CaptureBackgroundView(style: style)
        textView = Self.makeTextView()
        spaceBadge = CaptureBadgeView(style: style)
        reminderBadge = CaptureBadgeView(style: style)
        super.init(frame: .zero)

        background.autoresizingMask = [.width, .height]
        addSubview(background)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        placeholderLabel.wantsLayer = true
        placeholderLabel.setAccessibilityElement(false)
        promptLabel.setAccessibilityElement(false)
        [promptLabel, placeholderLabel, scrollView, spaceBadge, reminderBadge].forEach(addSubview)
        textView.setAccessibilityLabel("빠른 캡처")
        textView.setAccessibilityPlaceholderValue(Self.placeholder)
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 한 줄짜리 텍스트 뷰. 긴 글은 줄을 바꾸지 않고 옆으로 흐른다.
    private static func makeTextView() -> CaptureTextView {
        let view = CaptureTextView(frame: .zero)
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

    // MARK: - 내용

    /// 스페이스와 리마인더 표시, 시간 표현의 밑줄을 바꾼다.
    func apply(
        space: CaptureBadgeView.Content?,
        reminder: CaptureBadgeView.Content?,
        timeRange: NSRange?,
        animated: Bool
    ) {
        spaceBadge.apply(space, animated: animated)
        reminderBadge.apply(reminder, animated: animated)
        underline(timeRange)
        setPlaceholderVisible(textView.string.isEmpty, animated: animated)
        needsLayout = true
    }

    var spaceContent: CaptureBadgeView.Content? { spaceBadge.alphaValue > 0 ? spaceBadge.content : nil }
    var reminderContent: CaptureBadgeView.Content? { reminderBadge.alphaValue > 0 ? reminderBadge.content : nil }
    var isPlaceholderVisible: Bool { placeholderLabel.alphaValue > 0 }
    var timeUnderlineRange: NSRange? { underlinedRange }

    /// 알아들은 시간 표현에 밑줄을 긋는다. 글 저장소가 아니라 배치 쪽의 임시 속성이라 조합 중인 글자를 건드리지 않는다.
    private func underline(_ range: NSRange?) {
        guard let layoutManager = textView.layoutManager else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
        underlinedRange = range.flatMap { NSIntersectionRange($0, whole).length > 0 ? NSIntersectionRange($0, whole) : nil }
        guard let underlinedRange else { return }
        layoutManager.addTemporaryAttributes(
            [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: style.color(.text)],
            forCharacterRange: underlinedRange
        )
    }

    /// 자리 글자는 나타날 때만 `dur` 동안 움직인다. 글자를 치기 시작하면 바로 비킨다(친 글자와 겹쳐 보이지 않게).
    private func setPlaceholderVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        guard placeholderLabel.alphaValue != alpha else { return }
        guard animated, visible else {
            placeholderLabel.alphaValue = alpha
            return
        }
        style.animate { placeholderLabel.animator().alphaValue = alpha }
    }

    func refreshTheme() {
        let theme = style.theme
        background.refreshTheme()
        promptLabel.font = style.promptFont
        promptLabel.textColor = style.color(.text3)
        placeholderLabel.font = style.inputFont
        placeholderLabel.textColor = style.color(.text3)
        textView.font = style.inputFont
        textView.textColor = style.color(.text)
        textView.typingAttributes = [.font: style.inputFont, .foregroundColor: style.color(.text)]
        textView.insertionPointColor = style.color(.accent)
        textView.caretWidth = theme.component(.caretWidth)
        textView.selectedTextAttributes = [.backgroundColor: style.color(.hover)]
        spaceBadge.refresh()
        reminderBadge.refresh()
        underline(underlinedRange)
        needsLayout = true
    }

    // MARK: - 배치

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let theme = style.theme
        let padding = theme.component(.capturePadding)
        let gap = theme.component(.captureGap)
        let valueGap = theme.component(.captureValueGap)
        background.frame = bounds

        func centered(_ size: NSSize, x: CGFloat) -> NSRect {
            NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        }

        let promptWidth = style.textWidth(of: promptLabel)
        promptLabel.frame = style.labelFrame(
            promptLabel, textX: padding, textWidth: promptWidth, centeredIn: bounds.height
        )

        // 오른쪽 끝에서부터: 리마인더, 그 왼쪽에 스페이스. 없는 것은 자리가 없다.
        var trailing = bounds.width - padding
        for badge in [reminderBadge, spaceBadge] {
            let width = badge.fittingWidth
            guard width > 0 else {
                badge.frame = NSRect(x: trailing, y: 0, width: 0, height: bounds.height)
                continue
            }
            badge.frame = NSRect(x: trailing - width, y: 0, width: width, height: bounds.height)
            trailing = badge.frame.minX - gap - valueGap
        }

        let inputX = padding + promptWidth + gap
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: style.inputFont).rounded(.up)
            ?? theme.lineHeight(.capture)
        let inputFrame = centered(NSSize(width: max(0, trailing - inputX), height: lineHeight), x: inputX)
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
