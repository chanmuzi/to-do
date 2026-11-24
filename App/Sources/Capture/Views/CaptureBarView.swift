import AppKit
import SwiftUI
import Theme

/// 캡처 바의 한 줄(spec 7, 화면 3): `>` / 입력 칸 / 스페이스 / 리마인더. 닫는 버튼은 없다.
final class CaptureBarView: NSView {
    private let style: CaptureStyle
    private let background: CaptureBackgroundView
    private let switchHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let modelHost = ModelPickerHost(rootView: AnyView(EmptyView()))
    func setModelPicker(_ picker: AnyView?) {
        modelHost.rootView = AnyView(picker.fixedSize())
        modelHost.isHidden = picker == nil
        needsLayout = true
    }

    private let recentHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var recent: CaptureRecentRequest?
    var onRecent: (UUID) -> Void = { _ in }
    var recentHeight: CGFloat { recent == nil ? 0 : style.theme.component(.captureRecentHeight) }

    func setRecent(_ recent: CaptureRecentRequest?) {
        self.recent = recent
        if let recent {
            recentHost.rootView = AnyView(CaptureRecentRow(theme: style.theme, recent: recent) { [weak self] in
                self?.onRecent(recent.id)
            })
        }
        recentHost.isHidden = recent == nil
        needsLayout = true
    }

    var onSwitch: () -> Void = {}
    private var mode: CaptureCoordinator.Mode = .memo
    func setMode(_ value: CaptureCoordinator.Mode) {
        mode = value
        refreshTheme()
    }
    let input: CommandInputField
    let textView: CaptureTextView
    private let spaceBadge: CaptureBadgeView
    private let reminderBadge: CaptureBadgeView
    private var underlinedRanges: [NSRange] = []

    static let placeholder = "메모나 할 일을 적으세요"

    init(style: CaptureStyle) {
        self.style = style
        background = CaptureBackgroundView(style: style)
        textView = CaptureTextView(theme: style.theme)
        input = CommandInputField(theme: style.theme, editor: textView)
        spaceBadge = CaptureBadgeView(style: style)
        reminderBadge = CaptureBadgeView(style: style)
        super.init(frame: .zero)

        background.autoresizingMask = [.width, .height]
        addSubview(background)

        [recentHost, switchHost, input, spaceBadge, reminderBadge, modelHost].forEach(addSubview)
        input.setAccessibilityLabel("빠른 캡처")
        textView.setAccessibilityPlaceholderValue(Self.placeholder)
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    // MARK: - 내용

    /// 스페이스와 리마인더 표시, 시간 표현의 밑줄을 바꾼다.
    func apply(
        space: CaptureBadgeView.Content?,
        reminder: CaptureBadgeView.Content?,
        timeRanges: [NSRange],
        animated: Bool
    ) {
        spaceBadge.apply(space, animated: animated)
        reminderBadge.apply(reminder, animated: animated)
        underline(timeRanges)
        needsLayout = true
    }

    var spaceContent: CaptureBadgeView.Content? { spaceBadge.alphaValue > 0 ? spaceBadge.content : nil }
    var reminderContent: CaptureBadgeView.Content? { reminderBadge.alphaValue > 0 ? reminderBadge.content : nil }
    var isPlaceholderVisible: Bool { textView.string.isEmpty }
    var timeUnderlineRanges: [NSRange] { underlinedRanges }

    /// 알아들은 시간 표현에 밑줄을 긋는다. 날과 시각을 떨어뜨려 적었으면 두 곳이다.
    /// 글 저장소가 아니라 배치 쪽의 임시 속성이라 조합 중인 글자를 건드리지 않는다.
    private func underline(_ ranges: [NSRange]) {
        guard let layoutManager = textView.layoutManager else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
        underlinedRanges = ranges.map { NSIntersectionRange($0, whole) }.filter { $0.length > 0 }
        for range in underlinedRanges {
            layoutManager.addTemporaryAttributes(
                [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: style.color(.text)],
                forCharacterRange: range
            )
        }
    }

    func refreshTheme() {
        background.refreshTheme()
        let theme = style.theme
        let label = mode == .memo ? "요청으로 전환" : "메모로 전환"
        switchHost.rootView = AnyView(Button { [weak self] in self?.onSwitch() } label: {
            Group {
                if mode == .request { AgentFace(theme: theme) }
                else { Text(">").font(Font(style.promptFont)) }
            }.frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
        }.buttonStyle(SettingsButton(theme: theme, selected: false)).accessibilityLabel(label))
        let placeholder = mode == .request ? "에이전트에게 요청하기" : Self.placeholder
        input.setAccessibilityLabel(mode == .request ? "에이전트에게 요청" : "빠른 캡처")
        textView.setAccessibilityPlaceholderValue(placeholder)
        input.apply(font: style.inputFont, ink: style.color(.text), placeholder: placeholder,
                    placeholderInk: style.color(.text3))
        spaceBadge.refresh()
        reminderBadge.refresh()
        underline(underlinedRanges)
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
        let rowHeight = theme.component(.captureHeight)
        recentHost.frame = NSRect(x: 0, y: rowHeight, width: bounds.width, height: recentHeight)

        func centered(_ size: NSSize, x: CGFloat) -> NSRect {
            NSRect(x: x, y: ((rowHeight - size.height) / 2).rounded(), width: size.width, height: size.height)
        }

        let buttonSize = theme.component(.iconButton)
        let inset = theme.component(.agentChipGap)
        switchHost.frame = centered(NSSize(width: buttonSize, height: buttonSize), x: padding - inset)
        let promptWidth = buttonSize - inset * 2

        // 오른쪽 끝에서부터: 리마인더, 그 왼쪽에 스페이스. 없는 것은 자리가 없다.
        var trailing = bounds.width - padding
        if mode == .request && !modelHost.isHidden {
            let size = modelHost.fittingSize
            modelHost.frame = centered(size, x: trailing - size.width)
            trailing = modelHost.frame.minX - gap
        }
        for badge in [reminderBadge, spaceBadge] {
            let width = badge.fittingWidth
            guard width > 0 else {
                badge.frame = NSRect(x: trailing, y: 0, width: 0, height: rowHeight)
                continue
            }
            badge.frame = NSRect(x: trailing - width, y: 0, width: width, height: rowHeight)
            trailing = badge.frame.minX - gap - valueGap
        }

        let inputX = padding + promptWidth + gap
        let height = ceil(input.intrinsicContentSize.height)
        input.frame = centered(NSSize(width: max(0, trailing - inputX), height: height),
                               x: inputX - CaptureStyle.labelInset)
    }
}


private final class ModelPickerHost: NSHostingView<AnyView> {
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }
}
