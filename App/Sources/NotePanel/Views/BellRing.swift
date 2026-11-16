import AppKit

/// 임박한 리마인더의 종이 흔들리는 움직임(spec 15): 1.6초 주기, 뒤 40%에서만 14도, -12도, 6도.
/// 종 고리 쪽(위에서 12% 지점)을 축으로 돈다. 값은 spec 15의 표와 시안의 `ring` 키프레임을 옮긴 것이다.
enum BellRing {
    static let animationKey = "panel.bell-ring"
    private static let period: CFTimeInterval = 1.6
    private static let keyTimes: [NSNumber] = [0, 0.6, 0.7, 0.8, 0.9, 1]
    private static let degrees: [CGFloat] = [0, 0, 14, -12, 6, 0]
    private static let pivotFromTop: CGFloat = 0.12

    static func animation(for layer: CALayer) -> CAKeyframeAnimation {
        let size = layer.bounds.size
        let pivotY = layer.isGeometryFlipped ? size.height * pivotFromTop : size.height * (1 - pivotFromTop)
        // 레이어의 변환은 anchorPoint를 원점으로 한다. 축까지 옮겨 돌리고 되돌린다.
        let offset = CGPoint(
            x: size.width / 2 - layer.anchorPoint.x * size.width,
            y: pivotY - layer.anchorPoint.y * size.height
        )
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = degrees.map { degree in
            var transform = CATransform3DMakeTranslation(offset.x, offset.y, 0)
            transform = CATransform3DRotate(transform, -degree * .pi / 180, 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -offset.x, -offset.y, 0))
        }
        animation.keyTimes = keyTimes
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        return animation
    }
}
