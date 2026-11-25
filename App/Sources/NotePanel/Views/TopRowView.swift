import AppKit
import Theme
import DateTime

/// 노트 창의 상단 줄(spec 5.1, 5.2). 요소 자리는 `TopRowLayout`이, 내용과 색은 `TopRowState`가 정한다.
/// 이 줄을 끌면 창이 움직이고(spec 4.1), 제목을 누르면 그 자리에서 고친다.
final class TopRowView: NSView {
    struct Actions {
        var agent: () -> Void = {}
        var more: (NSView) -> Void = { _ in }
        var reminder: () -> Void = {}
        var pin: () -> Void = {}
        var problem: (NSView) -> Void = { _ in }
        var titleChanged: (String) -> Void = { _ in }
        var titleEditingChanged: (Bool) -> Void = { _ in }
        var titleReturned: () -> Void = {}
    }

    var actions = Actions()

    private let style: PanelStyle
    var allowsAgent = true
    var agentState: AgentFaceState = .idle {
        didSet { if oldValue != agentState { agentButton.showFace(agentState) } }
    }
    private let agentButton: IconButton
    let closeButton: IconButton
    private let clockButton: IconButton
    private let divider = NSView()
    var underlineMarkedText: Bool {
        get { title.underlineMarkedText }
        set { title.underlineMarkedText = newValue }
    }
    private let title: TitleField
    private let moreButton: IconButton
    private let problemButton: IconButton
    private let pinButton: IconButton
    private var state: TopRowState?
    private var animatesPinPlacement = false
    private var animatesClockPlacement = false
    private var clockTargetFrame: CGRect?
    private var clockFade: Task<Void, Never>?
    private var pinTargetFrame: CGRect?
    /// 저장 문제 표시의 자리. 표시가 다 사라질 때까지 자리를 지킨다.
    private var holdsProblemSlot = false
    /// 표시가 다 사라진 뒤 자리를 비우는 일(`dur` 뒤). 그사이 다시 바뀌면 취소한다.
    private var problemFade: Task<Void, Never>?
    private var mouseDownEvent: NSEvent?

    init(style: PanelStyle) {
        self.style = style
        agentButton = IconButton(style: style, symbolName: "", iconSize: .iconLarge, label: "에이전트 열기")
        agentButton.showFace()
        closeButton = IconButton(style: style, symbolName: "xmark", iconSize: .iconMedium, label: "창 닫기")
        clockButton = IconButton(style: style, symbolName: "clock", iconSize: .iconMedium, label: "이 노트의 일정")
        title = TitleField(style: style)
        moreButton = IconButton(style: style, symbolName: "ellipsis", iconSize: .iconMedium, label: "더 보기")
        problemButton = IconButton(
            style: style, symbolName: "exclamationmark.triangle", iconSize: .iconMedium, label: ""
        )
        clockButton.isHidden = true
        clockButton.alphaValue = 0
        pinButton = IconButton(
            style: style, symbolName: "pin.fill", iconSize: .iconMedium, label: "항상 위에 고정", tint: .text3
        )
        super.init(frame: .zero)
        divider.wantsLayer = true
        [agentButton, closeButton, clockButton, divider, title, moreButton, problemButton, pinButton]
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
        agentButton.onPress = { [unowned self] in actions.agent() }
        clockButton.onPress = { [unowned self] in actions.reminder() }
        moreButton.onPress = { [unowned self] in actions.more(moreButton) }
        problemButton.onPress = { [unowned self] in actions.problem(problemButton) }
        pinButton.onPress = { [unowned self] in actions.pin() }
        title.onChange = { [unowned self] in actions.titleChanged($0) }
        title.onReturn = { [unowned self] in actions.titleReturned() }
        title.onEditingChange = { [unowned self] in
            needsLayout = true
            actions.titleEditingChanged($0)
        }
    }

    var recognizesDates: Bool {
        get { title.recognizesDates }
        set { title.recognizesDates = newValue }
    }
    var onAcceptDate: ((InlineDateAcceptance) throws -> InlineDateEffect)? {
        get { title.onAcceptDate }
        set { title.onAcceptDate = newValue }
    }
    var onDateError: (Error) -> Void {
        get { title.onDateError }
        set { title.onDateError = newValue }
    }
    var isEditingTitle: Bool { title.isEditing }
    /// 더 보기 메뉴를 띄울 기준(단축키로 열 때도 쓴다).
    var moreAnchor: NSView { moreButton }
    var reminderAnchor: NSView { clockButton }

    func beginTitleEditing() {
        guard let state else { return }
        title.beginEditing(title: state.isTitlePlaceholder ? "" : state.title)
    }

    func endTitleEditing() {
        title.endEditing()
    }

    // MARK: - 상태

    func apply(_ state: TopRowState, animated: Bool) {
        let previous = self.state
        let movesOnHover = animated && previous?.hoverControlsAlpha != state.hoverControlsAlpha && style.transitionDuration > 0
        animatesPinPlacement = movesOnHover && previous?.pin.isOn == true && state.pin.isOn
        animatesClockPlacement = movesOnHover && previous?.hasSchedules == true && state.hasSchedules
        self.state = state
        divider.layer?.backgroundColor = style.cgColor(.line, in: self)
        title.paletteID = state.paletteID
        title.show(
            title: state.title, color: state.titleColor,
            animated: animated
        )
        if let label = state.clockLabel {
            clockButton.set(symbolName: "clock", tint: state.clockColor, animated: animated)
            clockButton.toolTip = label
            clockButton.setAccessibilityLabel(label)
        }
        if state.hasSchedules != (previous?.hasSchedules == true) {
            clockFade?.cancel()
            clockFade = style.fade(clockButton, visible: state.hasSchedules, animated: animated) { [weak self] in
                guard let self, self.state?.hasSchedules == false else { return }
                clockButton.isHidden = true
                needsLayout = true
            }
        }
        pinButton.set(symbolName: state.pin.symbolName, tint: state.pin.color, animated: animated)
        pinButton.setAccessibilityValue(state.pin.isOn ? "켜짐" : "꺼짐")
        applyProblem(state.problemLabel, wasShown: previous?.problemLabel != nil, animated: animated)

        let alphas: [(NSView, Double)] = [
            (agentButton, allowsAgent ? (agentState == .idle ? state.hoverControlsAlpha : 1) : 0), (closeButton, state.hoverControlsAlpha), (divider, state.hoverControlsAlpha),
            (moreButton, state.hoverControlsAlpha),
            (pinButton, state.pin.alpha),
        ]
        if animated {
            style.animate { alphas.forEach { $0.0.animator().alphaValue = $0.1 } }
        } else {
            alphas.forEach { $0.0.alphaValue = $0.1 }
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// 저장 문제 표시는 알파로 `dur` 동안 나타나고 사라진다(규칙 8). 사라지는 동안에는 자리를 지킨다.
    private func applyProblem(_ label: String?, wasShown: Bool, animated: Bool) {
        if let label { problemButton.setAccessibilityLabel(label) }
        let isShown = label != nil
        guard isShown != wasShown else { return }
        if isShown { holdsProblemSlot = true }
        problemFade?.cancel()
        problemFade = style.fade(problemButton, visible: isShown, animated: animated) { [weak self] in
            guard let self else { return }
            problemFade = nil
            // 다 사라졌으면 자리를 비운다. 움직임이 어디까지 갔든 끝의 값으로 놓는다.
            guard self.state?.problemLabel == nil else { return }
            problemButton.alphaValue = 0
            problemButton.isHidden = true
            holdsProblemSlot = false
            needsLayout = true
        }
    }

    func refreshTheme() {
        title.refreshTheme()
        [moreButton, problemButton, pinButton, closeButton, clockButton].forEach { $0.refresh() }
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
                // 고치는 동안에는 남는 너비를 다 쓴다.
                titleWidth: title.isEditing ? .greatestFiniteMagnitude : title.idealWidth,
                hasSchedules: state?.hasSchedules == true,
                showsControls: state?.hoverControlsAlpha == 1,
                allowsAgent: allowsAgent,
                hasAgentActivity: agentState != .idle,
                isPinned: state?.pin.isOn == true,
                showsProblem: holdsProblemSlot
            ),
            metrics: TopRowLayout.Metrics(
                height: style.theme.shape(.chromeHeight),
                paddingLeading: theme.space(.sp3),
                // 줄 끝에 보이는 닫기와 평소 핀의 중심은 이전 자리와 같다.
                paddingTrailing: theme.component(.noteTopPaddingEnd),
                gap: theme.component(.chromeGap),
                iconButton: theme.component(.noteTopButtonSize),
                dividerWidth: theme.shape(.borderWidth),
                buttonGap: theme.component(.noteTopButtonGap)
            )
        )
        agentButton.frame = frames.agent
        agentButton.setAccessibilityElement(frames.agent != .zero)
        closeButton.frame = frames.close
        let dividerHeight = theme.component(.iconMedium)
        divider.frame = CGRect(x: frames.divider.minX, y: (bounds.height - dividerHeight) / 2,
                               width: frames.divider.width, height: dividerHeight)
        title.place(in: frames.title)
        moreButton.frame = frames.more
        // 사라지는 중인 것은 자리가 없어져도 마지막 자리에서 사라진다.
        if let problem = frames.problem { problemButton.frame = problem }
        // 사라지는 시계는 마지막 자리에서 전환을 마친다.
        if frames.clock != .zero || clockButton.isHidden {
            place(clockButton, at: frames.clock, target: &clockTargetFrame, animated: animatesClockPlacement)
        }
        place(pinButton, at: frames.pin, target: &pinTargetFrame, animated: animatesPinPlacement)
        animatesClockPlacement = false
        animatesPinPlacement = false
    }

    private func place(_ button: IconButton, at frame: CGRect, target: inout CGRect?, animated: Bool) {
        guard target != frame else { return }
        target = frame
        if animated {
            style.animate { button.animator().frame = frame }
        } else {
            button.frame = frame
        }
    }

    // MARK: - 끌기와 제목 누르기

    /// 버튼과 고치는 중인 제목만 스스로 마우스를 받는다. 나머지는 이 줄이 받아 창을 끈다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is IconButton { return hit }
            if current === title, title.isEditing { return hit }
            view = current.superview
        }
        // 칸 사이와 구분선에서도 가까운 쪽이 누름을 받는다. 제목 쪽과 줄 끝은 끌 수 있다.
        let local = convert(point, from: superview)
        let controls = subviews.compactMap { $0 as? ClickableView }.filter {
            !$0.isHidden && $0.alphaValue > 0 && !$0.frame.isEmpty
                && local.y >= $0.frame.minY && local.y < $0.frame.maxY
        }
        let left = controls.filter { $0.frame.maxX <= local.x }.max { $0.frame.maxX < $1.frame.maxX }
        let right = controls.filter { $0.frame.minX > local.x }.min { $0.frame.minX < $1.frame.minX }
        guard let left, let right else { return self }
        return local.x < (left.frame.maxX + right.frame.minX) / 2 ? left : right
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(for: event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(for: event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(for: event) }

    private func updateCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if title.frame.contains(point) { title.titleCursor.set() } else { NSCursor.arrow.set() }
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
