import QuartzCore
import SwiftUI

extension MotionTokens {
    /// SwiftUI 전환.
    public var animation: Animation {
        .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
    }

    /// Core Animation, `NSAnimationContext`용 곡선.
    public var timingFunction: CAMediaTimingFunction { curve.timingFunction }
}

extension BezierCurve {
    public var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }
}

extension BezierCurve {
    /// CSS `cubic-bezier`와 같은 곡선에서 시간 비율(0~1)에 대한 진행 비율.
    package func progress(at time: Double) -> Double {
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
