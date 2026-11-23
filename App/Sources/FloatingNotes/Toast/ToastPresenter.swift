import AppKit
import Theme

/// 짧은 알림(토스트)을 띄우는 곳(D-041). 한 줄의 글과 동작 하나를 화면 가운데 아래쪽에 잠깐 보인다.
///
/// - 한 번에 하나만 뜬다. 새 알림이 오면 앞의 것을 바로 바꾼다.
/// - 앱을 앞으로 가져오지 않고 키 창도 되지 않는다(`ToastPanel`).
/// - `toast-hold` 동안 떠 있다가 `dur`, `ease`로 사라진다. 동작을 누르면 그 일을 하고 곧바로 사라지기 시작한다.
/// - 상태(`content`)는 움직임이 끝났는지에 기대지 않는다. 보이고 사라지는 일은 그 자리에서 정하고, 창을 내리는
///   일과 떠 있는 시간은 `TransitionTimer`가 잡는다(D-032의 7번).
final class ToastPresenter {
    /// 알림 하나의 내용. `kind`로 어떤 일의 알림인지 가른다(그 일이 끝나면 그 알림만 거둔다).
    struct Content: Equatable {
        var kind: String
        var message: String
        var actionTitle: String
        var face: AgentFaceState?
    }

    private let theme: Theme
    private var panel: ToastPanel?
    private var view: ToastView?
    private var action: (() -> Void)?
    private var holdTimer: Task<Void, Never>?
    private var hideTimer: Task<Void, Never>?

    /// 지금 떠 있는 알림. 사라지기 시작하면 곧바로 `nil`이다.
    private(set) var content: Content?

    /// 사라지는 시간. "동작 줄이기"면 0.
    var transitionDuration: () -> TimeInterval
    /// 떠 있는 시간. 시험에서 바꿔 넣는다.
    var holdDuration: TimeInterval

    init(theme: Theme) {
        self.theme = theme
        transitionDuration = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : theme.motion.duration
        }
        holdDuration = theme.motion.toastHold
    }

    var isVisible: Bool { content != nil }
    /// 확인용: 알림 창.
    var window: NSWindow? { panel }

    /// 알림을 띄운다. 앞에 떠 있던 알림은 바로 바뀐다.
    /// - Parameters:
    ///   - screen: 띄울 화면. 없으면 주 화면.
    ///   - action: 동작을 눌렀을 때. 알림은 그 뒤 사라진다.
    func show(_ content: Content, on screen: NSScreen?, action: @escaping () -> Void) {
        cancelTimers()
        self.content = content
        self.action = action
        let panel = panel ?? ToastPanel()
        self.panel = panel
        let view = ToastView(theme: theme, message: content.message, actionTitle: content.actionTitle, face: content.face, working: content.kind == "agent-working")
        view.actionButton.onPress = { [unowned self] in performAction() }
        panel.contentView = view
        self.view = view
        if let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let maxWidth = theme.component(.captureWidth)
            panel.setFrame(
                ToastPlacement.frame(
                    size: view.fittingSize(maxWidth: maxWidth), visibleFrame: visible,
                    bottomFraction: theme.tokens.ratio(.toastBottomScreen)
                ),
                display: false
            )
        }
        // 띄우는 즉시 누를 수 있게 자리를 잡아 둔다(그리기를 기다리지 않는다).
        view.layoutSubtreeIfNeeded()
        let duration = transitionDuration()
        let wasShown = panel.isVisible && panel.alphaValue > 0
        if !wasShown { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        animate(duration) { panel.animator().alphaValue = 1 }
        if duration == 0 { panel.alphaValue = 1 }
        holdTimer = TransitionTimer.after(holdDuration) { [weak self] in self?.dismiss() }
    }

    /// 그 일의 알림이 떠 있으면 거둔다(되돌릴 수 없게 됐을 때 등).
    func dismiss(kind: String) {
        guard content?.kind == kind else { return }
        dismiss()
    }

    /// 알림을 거둔다. `dur` 동안 흐려진 뒤 창이 내려간다.
    func dismiss() {
        guard content != nil, let panel else { return }
        cancelTimers()
        content = nil
        action = nil
        let duration = transitionDuration()
        animate(duration) { panel.animator().alphaValue = 0 }
        hideTimer = TransitionTimer.after(duration) { [weak panel] in
            panel?.alphaValue = 0
            panel?.orderOut(nil)
        }
    }

    /// 동작을 누른 것과 같다(단추, 손쉬운 사용, 시험).
    func performAction() {
        guard let action else { return }
        dismiss()
        action()
    }

    private func cancelTimers() {
        holdTimer?.cancel()
        holdTimer = nil
        hideTimer?.cancel()
        hideTimer = nil
    }

    private func animate(_ duration: TimeInterval, _ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = theme.motion.timingFunction
            changes()
        }
    }

    isolated deinit {
        holdTimer?.cancel()
        hideTimer?.cancel()
        panel?.orderOut(nil)
    }
}
