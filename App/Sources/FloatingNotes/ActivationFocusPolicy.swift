import Carbon
import Foundation

/// 첫 실행과 비활성 노트의 로컬 누름 기록. 한 활성화가 소비한 기록은 다음 활성화로 넘기지 않는다.
struct ActivationFocusPolicy {
    static let launchGrace: TimeInterval = 1
    static let pressLifetime: TimeInterval = 0.5

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false
    private var notePressAt: TimeInterval?

    mutating func launchFinished(at time: TimeInterval) {
        launchFinishedAt = time
    }

    mutating func notePressedWhileInactive(at time: TimeInterval) {
        notePressAt = time
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

    mutating func consumeActivation(at time: TimeInterval) -> ActivationDecision {
        let launching = launchFinishedAt.map { !hasSeenActivation && time - $0 < Self.launchGrace } ?? true
        let pendingAge = notePressAt.map { time - $0 }
        hasSeenActivation = true
        notePressAt = nil
        return ActivationDecision(launching: launching, pendingAge: pendingAge)
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
