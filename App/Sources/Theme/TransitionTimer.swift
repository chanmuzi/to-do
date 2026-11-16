import Foundation

/// 전환이 끝날 때 해야 하는 일(창 내리기, 끝의 값으로 놓기, 자리 비우기)을 시계로 잡는 곳.
///
/// 움직임이 끝났다는 알림(`NSAnimationContext`의 `completionHandler`)에 상태를 걸지 않는다. 화면이 꺼져 있거나
/// 잠겨 있으면 창의 움직임은 나아가지 않고 그 알림도 오지 않는다. 움직임은 보이는 꾸밈일 뿐이고, 상태는
/// 전환 시간이 지나면 움직임이 어디까지 갔든 여기서 바뀐다.
@MainActor
public enum TransitionTimer {
    /// `duration` 뒤에 `work`를 한다. 시간이 0이면("동작 줄이기") 그 자리에서 하고 `nil`을 돌려준다.
    /// 돌려받은 것을 `cancel()`하면 하지 않는다(그사이 반대쪽 전환이 시작됐을 때).
    public static func after(_ duration: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard duration > 0 else {
            work()
            return nil
        }
        return Task { @MainActor in
            guard (try? await Task.sleep(for: .seconds(duration))) != nil, !Task.isCancelled else { return }
            work()
        }
    }
}
