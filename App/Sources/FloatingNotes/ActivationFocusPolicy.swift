import Foundation

/// 앱이 앞으로 왔을 때 맨 앞 노트를 키 창으로 만들지(D-025).
///
/// 사용자가 앱을 일부러 앞으로 가져오면(⌘Tab, Dock) 맨 앞 노트가 키 창이 되어 키보드만으로 이어 쓸 수 있다.
/// 켜는 중에 오는 활성화는 뺀다: 켤 때 되살린 창은 키 창이 되지 않는다는 약속을 지킨다.
///
/// AppKit은 "켜면서 온 활성화"와 "나중에 사용자가 한 활성화"를 가려 주지 않는다(같은 알림이고, 뒤에서
/// 켠 실행에서는 켜면서 오는 활성화가 아예 없다). 그래서 다 켠 뒤 `launchGrace` 안에 온 첫 활성화만
/// 켜면서 온 것으로 본다.
struct ActivationFocusPolicy {
    /// 다 켠 뒤 이 시간 안에 온 첫 활성화는 켜면서 온 것으로 본다(초). 화면 값이 아니라 판단 기준이다.
    static let launchGrace: TimeInterval = 1

    private var launchFinishedAt: TimeInterval?
    private var hasSeenActivation = false

    /// 다 켰다(`applicationDidFinishLaunching`의 끝).
    mutating func launchFinished(at time: TimeInterval) {
        launchFinishedAt = time
    }

    /// 앱이 앞으로 왔다. 맨 앞 노트를 키 창으로 만들어도 되면 참.
    mutating func shouldFocusNote(activatedAt time: TimeInterval) -> Bool {
        defer { hasSeenActivation = true }
        // 아직 켜는 중이다.
        guard let launchFinishedAt else { return false }
        if !hasSeenActivation, time - launchFinishedAt < Self.launchGrace { return false }
        return true
    }
}
