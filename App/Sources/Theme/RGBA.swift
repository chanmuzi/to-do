import Foundation

/// sRGB 색 값. 성분은 0~1.
public struct RGBA: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 이 색에 `other`를 `fraction`(0~1)만큼 섞는다. CSS `color-mix(in srgb, …)`와 같다.
    public func mixed(with other: RGBA, fraction: Double) -> RGBA {
        let keep = 1 - fraction
        return RGBA(
            red: red * keep + other.red * fraction,
            green: green * keep + other.green * fraction,
            blue: blue * keep + other.blue * fraction,
            alpha: alpha * keep + other.alpha * fraction
        )
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
}
