import Foundation

/// 첫 실행의 창 복원과 실행 중의 앱 전환을 구분한다.
struct ActivationFocusPolicy {
    /// 다 켠 뒤 이 시간 안에 온 첫 활성화는 켜면서 온 것으로 본다(초). 화면 값이 아니라 판단 기준이다.
    static let launchGrace: TimeInterval = 1

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false

    /// 다 켰다(`applicationDidFinishLaunching`의 끝).
    mutating func launchFinished(at time: TimeInterval) {
        launchFinishedAt = time
    }

    /// 직접 고른 창이나 모달에 입력을 주는 활성화는 라이브러리로 돌리지 않는다.
    mutating func shouldShowLibrary(activatedAt time: TimeInterval, hasExplicitTarget: Bool = false) -> Bool {
        defer { hasSeenActivation = true }
        guard !hasExplicitTarget else { return false }
        // 아직 켜는 중이다.
        guard let launchFinishedAt else { return false }
        if !hasSeenActivation, time - launchFinishedAt < Self.launchGrace { return false }
        return true
    }
}
