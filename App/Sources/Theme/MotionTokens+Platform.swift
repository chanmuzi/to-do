import QuartzCore
import SwiftUI

extension MotionTokens {
    /// SwiftUI 전환.
    public var animation: Animation {
        .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
    }

    /// Core Animation, `NSAnimationContext`용 곡선.
    public var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2)
        )
    }
}
