import AppKit

/// 임박한 리마인더의 종이 흔들리는 움직임(spec 15). 주기, 흔들리는 구간, 각도, 축, 곡선은
/// `tokens.json`의 `motion.bell-*`에서 온다(`BellMotion`).
public enum BellRing {
    public static let animationKey = "panel.bell-ring"

    public static func animation(for layer: CALayer, motion: BellMotion) -> CAKeyframeAnimation {
        let size = layer.bounds.size
        let pivotY = layer.isGeometryFlipped
            ? size.height * motion.pivotFromTop
            : size.height * (1 - motion.pivotFromTop)
        // 레이어의 변환은 anchorPoint를 원점으로 한다. 축까지 옮겨 돌리고 되돌린다.
        let offset = CGPoint(
            x: size.width / 2 - layer.anchorPoint.x * size.width,
            y: pivotY - layer.anchorPoint.y * size.height
        )
        let keyframes = motion.keyframes
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = keyframes.map { frame in
            var transform = CATransform3DMakeTranslation(offset.x, offset.y, 0)
            transform = CATransform3DRotate(transform, -frame.degrees * .pi / 180, 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -offset.x, -offset.y, 0))
        }
        animation.keyTimes = keyframes.map { NSNumber(value: $0.time) }
        animation.duration = motion.period
        animation.repeatCount = .infinity
        animation.timingFunction = motion.curve.timingFunction
        animation.isRemovedOnCompletion = false
        return animation
    }
}
