import Foundation

/// 사용자가 덮어쓴 토큰. 키는 `구역.키` 꼴이고 값은 `tokens.json`과 같은 표기다.
///
/// 예: `color.light.accent` = `#1A8F4C`, `type.fs-body` = `14px`, `material.opacity` = `.85`,
/// `fonts.font-body` = `"SF Pro"`, `palette.tint-1` = `#778899`.
public struct ThemeOverrides: Hashable, Codable, Sendable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public var isEmpty: Bool { values.isEmpty }

    public func setting(_ key: String, to value: String) -> ThemeOverrides {
        ThemeOverrides(values: values.merging([key: value]) { _, new in new })
    }

    public func removing(_ key: String) -> ThemeOverrides {
        ThemeOverrides(values: values.filter { $0.key != key })
    }

    /// 색 토큰의 키.
    public static func key(_ token: ColorToken, _ appearance: ThemeAppearance) -> String {
        "color.\(appearance.rawValue).\(token.rawValue)"
    }
}
