import AppKit
import SwiftUI

extension Theme {
    /// 글자 역할의 글꼴. `size`, `weight`를 주면 토큰 값 대신 쓴다(예: 임박한 리마인더의 굵기).
    public func nsFont(_ style: TextStyle, size: CGFloat? = nil, weight: CGFloat? = nil) -> NSFont {
        let spec = tokens.textStyle(style)
        return FontResolver.font(
            families: spec.families, size: size ?? spec.size, weight: weight ?? spec.weight
        )
    }

    public func font(_ style: TextStyle, size: CGFloat? = nil, weight: CGFloat? = nil) -> Font {
        Font(nsFont(style, size: size, weight: weight) as CTFont)
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
