import AppKit
import SwiftUI

extension Theme {
    /// 지금 모양에서의 색 값.
    public func rgba(_ token: ColorToken) -> RGBA {
        tokens.color(token, appearance)
    }

    /// 그리는 뷰의 라이트, 다크를 따라가는 색.
    public func nsColor(_ token: ColorToken) -> NSColor {
        Self.dynamicColor(light: tokens.color(token, .light), dark: tokens.color(token, .dark))
    }

    public func color(_ token: ColorToken) -> Color {
        Color(nsColor: nsColor(token))
    }

    /// 노트 바탕색. `paletteID`가 `nil`이면 `surface`.
    public func noteBackgroundNSColor(paletteID: String?) -> NSColor {
        Self.dynamicColor(
            light: tokens.noteBackground(paletteID: paletteID, .light),
            dark: tokens.noteBackground(paletteID: paletteID, .dark)
        )
    }

    public func noteBackgroundColor(paletteID: String?) -> Color {
        Color(nsColor: noteBackgroundNSColor(paletteID: paletteID))
    }

    /// 지금 모양에서의 그림자 겹.
    public func shadow(_ token: ShadowToken) -> [ShadowLayer] {
        tokens.shadow(token, appearance)
    }

    private static func dynamicColor(light: RGBA, dark: RGBA) -> NSColor {
        let lightColor = light.nsColor
        let darkColor = dark.nsColor
        return NSColor(name: nil) { appearance in
            ThemeAppearance(appearance) == .dark ? darkColor : lightColor
        }
    }
}
