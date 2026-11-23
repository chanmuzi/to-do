import AppKit
import SwiftUI

extension Theme {
    /// 글자 역할의 글꼴. `size`, `weight`를 주면 토큰 값 대신 쓴다(예: 임박한 리마인더의 굵기).
    public func nsFont(_ style: TextStyle, size: CGFloat? = nil, weight: CGFloat? = nil) -> NSFont {
        let spec = tokens.textStyle(style)
        let requestedWeight = weight ?? spec.weight
        let ceiling = tokens.textStyle(.uiStrong).weight
        return FontResolver.font(
            families: spec.families, size: size ?? spec.size, weight: requestedWeight,
            maximumWeight: requestedWeight <= ceiling ? ceiling : nil
        )
    }

    public func font(_ style: TextStyle, size: CGFloat? = nil, weight: CGFloat? = nil) -> Font {
        Font(nsFont(style, size: size, weight: weight) as CTFont)
    }

    /// 라이브러리의 시각은 본문 글꼴을 쓰고 숫자 폭만 맞춘다.
    package var libraryNumberFont: Font {
        font(.body, size: tokens.textStyle(.micro).size).monospacedDigit()
    }

    /// 줄 높이(pt).
    public func lineHeight(_ style: TextStyle) -> CGFloat {
        tokens.textStyle(style).lineHeight
    }

    /// 자간(pt).
    public func tracking(_ style: TextStyle) -> CGFloat {
        tokens.textStyle(style).tracking
    }
}
