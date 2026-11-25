import CoreGraphics
import Foundation
import Theme

/// 창 높이를 `dur`, `ease`로 옮기는 계산(spec 15, 19). 시간에 따른 높이만 내고, 창에 적용하는 일은 노트 창이 한다.
struct HeightTransition: Hashable {
    let from: CGFloat
    let to: CGFloat
    let duration: TimeInterval
    let curve: BezierCurve

    var isInstant: Bool { duration <= 0 || from == to }

    /// 시작한 지 `elapsed`초 뒤의 높이. 끝난 뒤에는 목표 높이다.
    func height(at elapsed: TimeInterval) -> CGFloat {
        guard !isInstant, elapsed < duration else { return to }
        let progress = curve.progress(at: max(0, elapsed) / duration)
        return (from + (to - from) * progress).rounded()
    }
}
