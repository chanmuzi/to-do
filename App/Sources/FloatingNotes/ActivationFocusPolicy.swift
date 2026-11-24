import Carbon
import Foundation

/// 비활성으로 돌아갈 때까지 창을 유지한 이유를 기억한다. 누름의 유효 시간은 첫 누름부터 센다.
struct ActivationFocusPolicy {
    static let launchGrace: TimeInterval = 1
    static let pressLifetime: TimeInterval = 0.5

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false
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
                         carbon: CarbonTarget = .noEvent, appKit: CarbonTarget = .noEvent,
                         window: ActivationDecision.WindowKind = .none, mouseAge: TimeInterval = .infinity,
                         keyAge: TimeInterval = .infinity) -> (reason: ActivationDecision.Reason, pendingAge: TimeInterval?, reused: Bool) {
        let launching = launchFinishedAt.map { !hasSeenActivation && time - $0 < Self.launchGrace } ?? true
        hasSeenActivation = true
        let age = pressAt.map { time - $0 }
        let recentPress = age.map { (0...Self.pressLifetime).contains($0) && $0 <= keyAge } == true
        if !recentPress { pressAt = nil }
        if let activeReason { return (activeReason, age, true) }

        let evidence = ActivationDecision(launching: launching, pendingAge: recentPress ? age : nil)
        let reason = evidence.reason(explicitTarget: explicitTarget, carbonWindow: carbon == .clickedWindow || appKit == .clickedWindow,
                                     window: window, mouseAge: mouseAge, keyAge: keyAge)
        let reused = reason == .localPress && pressAlreadyUsed
        if reason != .showLibrary {
            activeReason = reason
            if recentPress { pressAlreadyUsed = true }
        }
        return (reason, age, reused)
    }
}

struct ActivationDecision {
    enum WindowKind: String { case none, external, library, floatWindow }
    enum Reason: String { case launch, explicitTarget, carbonWindow, localPress, pointer, showLibrary }

    let launching: Bool
    let pendingAge: TimeInterval?

    /// 시스템 조회, 이벤트 전달 순서, 창 조작과 독립적인 판단이다.
    func reason(explicitTarget: Bool = false, carbonWindow: Bool = false,
                window: WindowKind = .none, mouseAge: TimeInterval = .infinity,
                keyAge: TimeInterval = .infinity) -> Reason {
        if launching { return .launch }
        if explicitTarget { return .explicitTarget }
        if carbonWindow { return .carbonWindow }
        let recent = 0...ActivationFocusPolicy.pressLifetime
        if let pendingAge, recent.contains(pendingAge), pendingAge <= keyAge { return .localPress }
        // 직전 클릭 뒤 키를 눌러 앱을 전환한 경우 포인터는 우연히 노트 위에 있을 수 있다.
        if window == .floatWindow, recent.contains(mouseAge), mouseAge <= keyAge { return .pointer }
        return .showLibrary
    }
}
