import AppKit

/// 라이트, 다크. `tokens.json`의 `color.light`, `color.dark`에 대응한다.
public enum ThemeAppearance: String, CaseIterable, Sendable {
    case light
    case dark

    public init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    public var nsAppearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}
