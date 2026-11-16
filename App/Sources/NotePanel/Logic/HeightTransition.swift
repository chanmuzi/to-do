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

extension BezierCurve {
    /// CSS `cubic-bezier`와 같은 곡선에서 시간 비율(0~1)에 대한 진행 비율.
    func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        guard time < 1 else { return 1 }
        func coordinate(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }
        // x(t)는 0~1에서 늘기만 한다. 이분법으로 x == time인 t를 찾는다.
        var low = 0.0
        var high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if coordinate(middle, x1, x2) < time {
                low = middle
            } else {
                high = middle
            }
        }
        return coordinate((low + high) / 2, y1, y2)
    }
}
