import CoreGraphics
import Foundation

/// `tokens.json`을 읽어 타입 있는 값으로 푼 것. 바뀌지 않는 값이고 어느 스레드에서나 쓸 수 있다.
/// 코드가 쓰는 토큰은 만들 때 모두 검증하므로 접근자는 실패하지 않는다.
public struct ThemeTokens: Hashable, Sendable {
    private let raw: RawTokens
    private let colors: [ThemeAppearance: [ColorToken: RGBA]]
    private let shadows: [ThemeAppearance: [ShadowToken: [ShadowLayer]]]
    private let textStyles: [TextStyle: TextStyleSpec]
    private let fontFamilies: [FontRole: [String]]
    private let spaces: [SpaceToken: CGFloat]
    private let shapes: [ShapeToken: CGFloat]
    private let components: [ComponentToken: CGFloat]

    /// 노트 본문 안쪽 여백(`doc-pad`).
    public let docPadding: ThemeInsets
    public let material: MaterialTokens
    public let motion: MotionTokens
    /// 팔레트(순서는 `tokens.json`과 같다).
    public let palette: [PaletteColor]
    public let accentPresets: [AccentPreset]

    public init(data: Data) throws {
        try self.init(raw: RawTokens(data: data))
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// 번들에 든 `tokens.json`.
    public static func bundled() throws -> ThemeTokens {
        try ThemeTokens(contentsOf: ThemeResources.tokensURL())
    }

    /// 덮어쓰기를 얹은 새 값. 모르는 키나 해석할 수 없는 값이면 던진다.
    public func applying(_ overrides: ThemeOverrides) throws -> ThemeTokens {
        try ThemeTokens(raw: raw.applying(overrides))
    }

    // MARK: - 접근자

    public func color(_ token: ColorToken, _ appearance: ThemeAppearance) -> RGBA {
        colors[appearance]![token]!
    }

    public func shadow(_ token: ShadowToken, _ appearance: ThemeAppearance) -> [ShadowLayer] {
        shadows[appearance]![token]!
    }

    public func textStyle(_ style: TextStyle) -> TextStyleSpec { textStyles[style]! }
    public func fontFamilies(_ role: FontRole) -> [String] { fontFamilies[role]! }
    public func space(_ token: SpaceToken) -> CGFloat { spaces[token]! }
    public func shape(_ token: ShapeToken) -> CGFloat { shapes[token]! }
    public func component(_ token: ComponentToken) -> CGFloat { components[token]! }

    public func paletteColor(id: String) -> PaletteColor? {
        palette.first { $0.id == id }
    }

    /// 노트 바탕색. `surface`에 팔레트 색을 `tint-mix`만큼 섞는다. 키가 없거나 모르는 키면 `surface`.
    public func noteBackground(paletteID: String?, _ appearance: ThemeAppearance) -> RGBA {
        let surface = color(.surface, appearance)
        guard let paletteID, let tint = paletteColor(id: paletteID) else { return surface }
        return surface.mixed(with: tint.color, fraction: material.tintMix)
    }

    /// 목록 줄 바탕색. 팔레트 색에 `tint-mix-row` 알파. 색 없음이면 `nil`.
    public func rowTint(paletteID: String?) -> RGBA? {
        guard let paletteID, let tint = paletteColor(id: paletteID) else { return nil }
        return tint.color.withAlpha(material.tintMixRow)
    }

    // MARK: - 풀기

    private init(raw: RawTokens) throws {
        func value(_ key: String) throws -> String {
            guard let value = raw.values[key] else { throw ThemeError.missingToken(key) }
            return value
        }
        func parse<T>(_ key: String, _ parser: (String) -> T?) throws -> T {
            let text = try value(key)
            guard let parsed = parser(text) else { throw ThemeError.invalidValue(key: key, value: text) }
            return parsed
        }
        func table<Token: CaseIterable & Hashable & RawRepresentable<String>, T>(
            _ prefix: String, _ parser: (String) -> T?
        ) throws -> [Token: T] {
            var result: [Token: T] = [:]
            for token in Token.allCases { result[token] = try parse("\(prefix).\(token.rawValue)", parser) }
            return result
        }

        var colors: [ThemeAppearance: [ColorToken: RGBA]] = [:]
        var shadows: [ThemeAppearance: [ShadowToken: [ShadowLayer]]] = [:]
        for appearance in ThemeAppearance.allCases {
            colors[appearance] = try table("color.\(appearance.rawValue)", TokenValueParser.color)
            shadows[appearance] = try table("color.\(appearance.rawValue)", TokenValueParser.shadow)
        }

        let fontFamilies: [FontRole: [String]] = try table("fonts", TokenValueParser.fontFamilies)
        var textStyles: [TextStyle: TextStyleSpec] = [:]
        for style in TextStyle.allCases {
            let keys = style.keys
            let size = try parse("type.\(keys.size)", TokenValueParser.points)
            let em = try keys.tracking.map { try parse("type.\($0)", TokenValueParser.em) } ?? 0
            textStyles[style] = TextStyleSpec(
                families: fontFamilies[keys.font]!,
                size: size,
                lineHeight: try parse("type.\(keys.lineHeight)", TokenValueParser.points),
                weight: CGFloat(try parse("type.\(keys.weight)", TokenValueParser.number)),
                tracking: size * CGFloat(em)
            )
        }

        self.raw = raw
        self.colors = colors
        self.shadows = shadows
        self.fontFamilies = fontFamilies
        self.textStyles = textStyles
        self.spaces = try table("space", TokenValueParser.points)
        self.shapes = try table("shape", TokenValueParser.points)
        self.components = try table("component", TokenValueParser.points)
        self.docPadding = try parse("component.doc-pad", TokenValueParser.insets)
        self.material = MaterialTokens(
            opacity: try parse("material.opacity", TokenValueParser.number),
            blur: try parse("material.blur", TokenValueParser.points),
            tintMix: try parse("material.tint-mix", TokenValueParser.fraction),
            tintMixRow: try parse("material.tint-mix-row", TokenValueParser.fraction)
        )
        self.motion = MotionTokens(
            duration: try parse("motion.dur", TokenValueParser.seconds),
            curve: try parse("motion.ease", TokenValueParser.bezier)
        )
        self.palette = try raw.paletteOrder.map { key in
            PaletteColor(
                id: key,
                name: raw.paletteNames[key] ?? key,
                color: try parse("palette.\(key)", TokenValueParser.color)
            )
        }
        self.accentPresets = try raw.accentPresets.enumerated().map { index, preset in
            func field(_ name: String) throws -> RGBA {
                let key = "accentPresets[\(index)].\(name)"
                guard let text = preset[name] else { throw ThemeError.missingToken(key) }
                guard let color = TokenValueParser.color(text) else {
                    throw ThemeError.invalidValue(key: key, value: text)
                }
                return color
            }
            guard let name = preset["name"] else { throw ThemeError.missingToken("accentPresets[\(index)].name") }
            return AccentPreset(
                name: name,
                light: try field("light"), dark: try field("dark"),
                onLight: try field("onLight"), onDark: try field("onDark")
            )
        }
    }
}
