import Foundation

/// `tokens.json`에서 테마가 쓰는 부분을 `구역.키` → 문자열로 편 것.
/// 덮어쓰기(`ThemeOverrides`)는 이 단계에서 문자열을 바꿔 끼운다.
struct RawTokens: Hashable, Sendable {
    /// 예: `type.fs-body` → `13px`, `color.dark.surface` → `#000000`, `palette.tint-1` → `#8E9AAF`.
    var values: [String: String]
    var paletteOrder: [String]
    var paletteNames: [String: String]
    var accentPresets: [[String: String]]

    static let symbolScaleSection = "iconOptical"
    private static let flatSections = ["fonts", "type", "space", "shape", "component", "material", "motion"]

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThemeError.malformedDocument("최상위가 객체가 아닙니다")
        }
        var values: [String: String] = [:]

        func absorb(_ object: Any?, prefix: String) throws {
            guard let section = object as? [String: String] else {
                throw ThemeError.malformedDocument("\(prefix) 구역이 문자열 표가 아닙니다")
            }
            for (key, value) in section { values["\(prefix).\(key)"] = value }
        }

        for name in Self.flatSections { try absorb(root[name], prefix: name) }
        // 아이콘마다의 눈대중 크기 보정(없으면 모두 1).
        if let optical = root[Self.symbolScaleSection] { try absorb(optical, prefix: Self.symbolScaleSection) }
        let color = root["color"] as? [String: Any]
        for appearance in ThemeAppearance.allCases {
            try absorb(color?[appearance.rawValue], prefix: "color.\(appearance.rawValue)")
        }

        guard let palette = root["palette"] as? [[String: String]] else {
            throw ThemeError.malformedDocument("palette가 배열이 아닙니다")
        }
        var order: [String] = []
        var names: [String: String] = [:]
        for entry in palette {
            guard let key = entry["key"], let name = entry["name"], let color = entry["color"] else {
                throw ThemeError.malformedDocument("palette 항목에 key, name, color가 필요합니다")
            }
            order.append(key)
            names[key] = name
            values["palette.\(key)"] = color
        }

        guard let presets = root["accentPresets"] as? [[String: String]] else {
            throw ThemeError.malformedDocument("accentPresets가 배열이 아닙니다")
        }

        self.values = values
        self.paletteOrder = order
        self.paletteNames = names
        self.accentPresets = presets
    }

    func applying(_ overrides: ThemeOverrides) throws -> RawTokens {
        var copy = self
        for (key, value) in overrides.values {
            guard values[key] != nil else { throw ThemeError.unknownOverrideKey(key) }
            copy.values[key] = value
        }
        return copy
    }
}
