import Carbon
import Foundation

/// 첫 실행의 창 복원과 실행 중의 앱 전환을 구분한다.
struct ActivationFocusPolicy {
    /// 다 켠 뒤 이 시간 안에 온 첫 활성화는 켜면서 온 것으로 본다(초). 화면 값이 아니라 판단 기준이다.
    static let launchGrace: TimeInterval = 1

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false
    private var hasPendingNotePress = false

    /// 다 켰다(`applicationDidFinishLaunching`의 끝).
    mutating func launchFinished(at time: TimeInterval) {
        launchFinishedAt = time
    }

    mutating func notePressedWhileInactive() {
        hasPendingNotePress = true
    }

    /// 창에 누름이 전달되기 전에 활성화된 경우에는 활성화 이벤트 자체에 클릭한 창이 들어 있다.
    static func activationClickedWindow(_ event: EventRef?) -> Bool {
        guard let event, GetEventClass(event) == kEventClassApplication,
              GetEventKind(event) == kEventAppActivated else { return false }
        var window: UnsafeMutableRawPointer?
        return GetEventParameter(event, EventParamName(kEventParamWindowRef), EventParamType(typeWindowRef),
                                 nil, MemoryLayout.size(ofValue: window), nil, &window) == noErr && window != nil
    }

    /// 직접 고른 창이나 모달에 입력을 주는 활성화는 라이브러리로 돌리지 않는다.
    mutating func shouldShowLibrary(activatedAt time: TimeInterval, hasExplicitTarget: Bool = false) -> Bool {
        defer {
            hasSeenActivation = true
            hasPendingNotePress = false
        }
        guard !hasPendingNotePress, !hasExplicitTarget else { return false }
        // 아직 켜는 중이다.
        guard let launchFinishedAt else { return false }
        if !hasSeenActivation, time - launchFinishedAt < Self.launchGrace { return false }
        return true
    }
}
