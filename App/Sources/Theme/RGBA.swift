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

    /// WCAG 상대 휘도는 선형 sRGB 성분의 가중합이다.
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 어두운 바탕에 올리는 회색 보조 글자의 최소 8비트 밝기.
    func readable(on background: RGBA) -> RGBA {
        let required = (background.luminance + 0.05) * 4.5 - 0.05
        guard luminance < required else { return self }
        let srgb = required <= 0.0031308 ? 12.92 * required : 1.055 * pow(required, 1 / 2.4) - 0.055
        let gray = min(1, ceil(srgb * 255) / 255)
        return RGBA(red: gray, green: gray, blue: gray)
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
}
