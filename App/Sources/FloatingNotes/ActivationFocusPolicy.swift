import Carbon
import Foundation

/// 비활성으로 돌아갈 때까지 창을 유지한 이유를 기억한다. 누름의 유효 시간은 첫 누름부터 센다.
struct ActivationFocusPolicy {
    static let launchGrace: TimeInterval = 1
    static let pressLifetime: TimeInterval = 0.5

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false
    private var hasResignedActive = false
    private var pressAt: TimeInterval?
    private var pressAlreadyUsed = false
    private var activeReason: ActivationDecision.Reason?

    mutating func launchFinished(at time: TimeInterval) {
        launchFinishedAt = time
    }

    mutating func windowPressedWhileInactive(at time: TimeInterval) {
        pressAt = time
        pressAlreadyUsed = false
    }

    mutating func didResignActive() {
        activeReason = nil
        hasResignedActive = true
    }

    /// 시스템이 앱을 먼저 활성화하고 누름을 나중에 전달하면 활성화 알림 때는 누름 기록이 없다.
    /// 포인터가 Float 창 위에 있으면 이만큼 기다려 누름이 오는지 본 뒤에 라이브러리를 올린다.
    static let latePressWait: TimeInterval = 0.25

    /// 근거 없이 활성화됐을 때 라이브러리를 바로 올릴지, 늦게 오는 누름을 기다릴지.
    static func waitsForLatePress(window: ActivationDecision.WindowKind) -> Bool {
        window == .floatWindow
    }

    /// 활성화 뒤에 그 창의 누름이 확인됐다. 같은 활성화의 다음 알림도 이 판단을 따른다.
    mutating func adoptLatePress() {
        activeReason = .localPress
    }

    /// 최소화 중인 창은 첫 검사에도 남을 수 있다. 두 번째 검사까지 창이 남으면 일반 앱 전환이다.
    mutating func finishPassiveReturn(_ history: ActivationHistory, previousLeftScreen: Bool,
                                      allowsAnimationWait: Bool) -> ActivationDecision.Reason? {
        if allowsAnimationWait, history.previous == .regular, !previousLeftScreen { return nil }
        let reason = ActivationDecision(launching: false, pendingAge: nil)
            .reason(history: hasResignedActive ? history : .init(), previousLeftScreen: previousLeftScreen)
        if reason == .appLeft { activeReason = reason }
        return reason
    }

    enum CarbonTarget: String { case noEvent, otherEvent, unspecified, clickedWindow }

    /// 알림이 어느 이벤트 안에서 왔는지와 창 인자의 유무를 구별해 기록한다.
    static func carbonTarget(_ event: EventRef?) -> CarbonTarget {
        guard let event else { return .noEvent }
        guard GetEventClass(event) == kEventClassApplication,
              GetEventKind(event) == kEventAppActivated else { return .otherEvent }
        var window: UnsafeMutableRawPointer?
        let status = GetEventParameter(event, EventParamName(kEventParamWindowRef), EventParamType(typeWindowRef),
                                       nil, MemoryLayout.size(ofValue: window), nil, &window)
        return status == noErr && window != nil ? .clickedWindow : .unspecified
    }

    mutating func decide(at time: TimeInterval, explicitTarget: Bool = false,
                         history: ActivationHistory = .init(), previousLeftScreen: Bool = false, carbon: CarbonTarget = .noEvent, appKit: CarbonTarget = .noEvent,
                         window: ActivationDecision.WindowKind = .none, mouseAge: TimeInterval = .infinity,
                         keyAge: TimeInterval = .infinity) -> (reason: ActivationDecision.Reason, pendingAge: TimeInterval?, reused: Bool) {
        let launching = launchFinishedAt.map { !hasSeenActivation && time - $0 < Self.launchGrace } ?? true
        hasSeenActivation = true
        let age = pressAt.map { time - $0 }
        let recentPress = age.map { (0...Self.pressLifetime).contains($0) && $0 <= keyAge } == true
        if !recentPress { pressAt = nil }
        if let activeReason { return (activeReason, age, true) }

        let evidence = ActivationDecision(launching: launching, pendingAge: recentPress ? age : nil)
        let reason = evidence.reason(history: hasResignedActive ? history : .init(), previousLeftScreen: previousLeftScreen, explicitTarget: explicitTarget, carbonWindow: carbon == .clickedWindow || appKit == .clickedWindow,
                                     window: window, mouseAge: mouseAge, keyAge: keyAge)
        let reused = reason == .localPress && pressAlreadyUsed
        if reason != .showLibrary && reason != .appLeft {
            activeReason = reason
            if recentPress { pressAlreadyUsed = true }
        }
        return (reason, age, reused)
    }
}

/// Float가 다시 활성화될 때까지 거친 외부 앱의 종류만 기록한다.
struct ActivationHistory {
    enum AppKind: String { case regular, accessory, prohibited, none }

    private(set) var previous: AppKind = .none
    private var sawRegular = false

    mutating func activated(_ kind: AppKind) {
        previous = kind
        if kind == .regular { sawRegular = true }
    }

    var returnedFromHelper: Bool {
        !sawRegular && (previous == .accessory || previous == .prohibited)
    }
}

struct ActivationDecision {
    enum WindowKind: String { case none, external, library, floatWindow }
    enum Reason: String { case launch, explicitTarget, carbonWindow, localPress, pointer, helperReturn, appLeft, showLibrary }

    let launching: Bool
    let pendingAge: TimeInterval?

    /// 시스템 조회, 이벤트 전달 순서, 창 조작과 독립적인 판단이다.
    func reason(history: ActivationHistory = .init(), previousLeftScreen: Bool = false, explicitTarget: Bool = false, carbonWindow: Bool = false,
                window: WindowKind = .none, mouseAge: TimeInterval = .infinity,
                keyAge: TimeInterval = .infinity) -> Reason {
        if launching { return .launch }
        if explicitTarget { return .explicitTarget }
        if carbonWindow { return .carbonWindow }
        let recent = 0...ActivationFocusPolicy.pressLifetime
        if let pendingAge, recent.contains(pendingAge), pendingAge <= keyAge { return .localPress }
        // 직전 클릭 뒤 키를 눌러 앱을 전환한 경우 포인터는 우연히 노트 위에 있을 수 있다.
        if window == .floatWindow, recent.contains(mouseAge), mouseAge <= keyAge { return .pointer }
        if history.previous == .regular && previousLeftScreen { return .appLeft }
        if history.returnedFromHelper { return .helperReturn }
        return .showLibrary
    }
}
