import AppKit
import Theme

/// 노트 창의 상단 줄(spec 5.1, 5.2). 요소 자리는 `TopRowLayout`이, 내용과 색은 `TopRowState`가 정한다.
/// 이 줄을 끌면 창이 움직이고(spec 4.1), 제목을 누르면 그 자리에서 고친다.
final class TopRowView: NSView {
    struct Actions {
        var more: (NSView) -> Void = { _ in }
        var add: () -> Void = {}
        var reminder: () -> Void = {}
        var pin: () -> Void = {}
        var problem: (NSView) -> Void = { _ in }
        var titleChanged: (String) -> Void = { _ in }
        var titleEditingChanged: (Bool) -> Void = { _ in }
        var titleReturned: () -> Void = {}
    }

    var actions = Actions()

    private let style: PanelStyle
    private let spaceBadge: SpaceBadgeView
    private let title: TitleField
    private let moreButton: IconButton
    private let addButton: IconButton
    private let problemButton: IconButton
    private let reminderBadge: ReminderBadgeView
    private let pinButton: IconButton
    private var state: TopRowState?
    /// 저장 문제 표시의 자리. 표시가 다 사라질 때까지 자리를 지킨다.
    private var holdsProblemSlot = false
    /// 표시가 다 사라진 뒤 자리를 비우는 일(`dur` 뒤). 그사이 다시 바뀌면 취소한다.
    private var problemFade: Task<Void, Never>?
    private var mouseDownEvent: NSEvent?

    init(style: PanelStyle) {
        self.style = style
        spaceBadge = SpaceBadgeView(style: style)
        title = TitleField(style: style)
        moreButton = IconButton(style: style, symbolName: "ellipsis", iconSize: .iconLarge, label: "더 보기")
        addButton = IconButton(style: style, symbolName: "plus", iconSize: .iconLarge, label: "새 노트")
        problemButton = IconButton(
            style: style, symbolName: "exclamationmark.triangle", iconSize: .iconMedium, label: ""
        )
        reminderBadge = ReminderBadgeView(style: style)
        pinButton = IconButton(
            style: style, symbolName: "pin.fill", iconSize: .iconMedium, label: "항상 위에 고정", tint: .text3
        )
        super.init(frame: .zero)
        [spaceBadge, title, moreButton, addButton, problemButton, reminderBadge, pinButton]
            .forEach(addSubview)
        problemButton.isHidden = true
        problemButton.alphaValue = 0
        connect()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    private func connect() {
        moreButton.onPress = { [unowned self] in actions.more(moreButton) }
        addButton.onPress = { [unowned self] in actions.add() }
        problemButton.onPress = { [unowned self] in actions.problem(problemButton) }
        reminderBadge.onPress = { [unowned self] in actions.reminder() }
        pinButton.onPress = { [unowned self] in actions.pin() }
        title.onChange = { [unowned self] in actions.titleChanged($0) }
        title.onReturn = { [unowned self] in actions.titleReturned() }
        title.onEditingChange = { [unowned self] in
            needsLayout = true
            actions.titleEditingChanged($0)
        }
    }

    var isEditingTitle: Bool { title.isEditing }
    /// 더 보기 메뉴를 띄울 기준(단축키로 열 때도 쓴다).
    var moreAnchor: NSView { moreButton }
    var reminderAnchor: NSView { state?.reminder == nil ? moreButton : reminderBadge }

    func beginTitleEditing() {
        guard let state else { return }
        title.beginEditing(title: state.isTitlePlaceholder ? "" : state.title)
    }

    func endTitleEditing() {
        title.endEditing()
    }

    // MARK: - 상태

    func apply(_ state: TopRowState, animated: Bool) {
        let hadProblem = self.state?.problem != nil || (self.state?.syncFailure == true && self.state?.reminder == nil)
        self.state = state
        spaceBadge.apply(state.space, color: state.spaceColor, animated: animated)
        title.show(
            title: state.title, isPlaceholder: state.isTitlePlaceholder, color: state.titleColor,
            animated: animated
        )
        reminderBadge.apply(state.reminder, animated: animated)
        pinButton.set(symbolName: state.pin.symbolName, tint: state.pin.color, animated: animated)
        pinButton.setAccessibilityValue(state.pin.isOn ? "켜짐" : "꺼짐")
        applyProblem(state.problem, wasShown: hadProblem, animated: animated)

        let alphas: [(NSView, Double)] = [
            (moreButton, state.hoverControlsAlpha),
            (addButton, state.hoverControlsAlpha), (pinButton, state.pin.alpha),
        ]
        if animated {
            style.animate { alphas.forEach { $0.0.animator().alphaValue = $0.1 } }
        } else {
            alphas.forEach { $0.0.alphaValue = $0.1 }
        }
        needsLayout = true
    }

    /// 저장 문제 표시는 알파로 `dur` 동안 나타나고 사라진다(규칙 8). 사라지는 동안에는 자리를 지킨다.
    private func applyProblem(_ problem: NoteProblem?, wasShown: Bool, animated: Bool) {
        if let problem { problemButton.setAccessibilityLabel(problem.accessibilityLabel) }
        let isShown = problem != nil || (state?.syncFailure == true && state?.reminder == nil)
        if problem == nil && isShown { problemButton.setAccessibilityLabel("예정 연동 실패") }
        guard isShown != wasShown else { return }
        if isShown { holdsProblemSlot = true }
        problemFade?.cancel()
        problemFade = style.fade(problemButton, visible: isShown, animated: animated) { [weak self] in
            guard let self else { return }
            problemFade = nil
            // 다 사라졌으면 자리를 비운다. 움직임이 어디까지 갔든 끝의 값으로 놓는다.
            guard self.state?.problem == nil, !(self.state?.syncFailure == true && self.state?.reminder == nil) else { return }
            problemButton.alphaValue = 0
            problemButton.isHidden = true
            holdsProblemSlot = false
            needsLayout = true
        }
    }

    func refreshTheme() {
        spaceBadge.refresh()
        title.refreshTheme()
        reminderBadge.refresh()
        [moreButton, addButton, problemButton, pinButton].forEach { $0.refresh() }
        needsLayout = true
    }

    // MARK: - 배치

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let theme = style.theme
        let frames = TopRowLayout(
            TopRowLayout.Input(
                width: bounds.width,
                spaceWidth: spaceBadge.fittingWidth,
                // 고치는 동안에는 남는 너비를 다 쓴다.
                titleWidth: title.isEditing ? .greatestFiniteMagnitude : title.idealWidth,
                reminderWidth: reminderBadge.fittingWidth,
                showsProblem: holdsProblemSlot
            ),
            metrics: TopRowLayout.Metrics(
                height: bounds.height,
                paddingLeading: theme.space(.sp3),
                // 핀 아이콘의 오른쪽 끝이 제목의 왼쪽 여백과 같은 거리에 오게 한다(좌우 균형).
                paddingTrailing: max(0, theme.space(.sp3) - pinButton.glyphSideInset),
                gap: theme.component(.chromeGap),
                iconButton: theme.component(.iconButton),
                buttonGap: theme.component(.iconButtonGap)
            )
        )
        spaceBadge.frame = frames.space ?? .zero
        let titleHeight = title.idealHeight
        title.frame = NSRect(
            x: frames.title.minX, y: ((bounds.height - titleHeight) / 2).rounded(),
            width: frames.title.width, height: titleHeight
        )
        moreButton.frame = frames.more
        addButton.frame = frames.add
        // 사라지는 중인 것은 자리가 없어져도 마지막 자리에서 사라진다.
        if let problem = frames.problem { problemButton.frame = problem }
        if let reminder = frames.reminder { reminderBadge.frame = reminder }
        pinButton.frame = frames.pin
    }

    // MARK: - 끌기와 제목 누르기

    /// 버튼과 리마인더, 고치는 중인 제목만 스스로 마우스를 받는다. 나머지는 이 줄이 받아 창을 끈다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is IconButton || current is ReminderBadgeView { return hit }
            if current === title, title.isEditing { return hit }
            view = current.superview
        }
        return self
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        title.endEditing()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        mouseDownEvent = nil
        window?.performDrag(with: start)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        if title.frame.contains(convert(event.locationInWindow, from: nil)) { beginTitleEditing() }
    }
}
