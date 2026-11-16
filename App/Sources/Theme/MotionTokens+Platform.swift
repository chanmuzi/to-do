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
