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
    private let ratios: [RatioToken: Double]
    private let counts: [CountToken: Int]
    private let symbolScales: [String: CGFloat]

    /// 노트 본문 안쪽 여백(`doc-pad`).
    public let docPadding: ThemeInsets
    public let material: MaterialTokens
    private let facePeriods: [AgentFaceTiming: TimeInterval]
    public func period(_ timing: AgentFaceTiming) -> TimeInterval { facePeriods[timing]! }
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

    /// 얹을 수 있는 덮어쓰기만 얹는다. 모르는 키나 해석할 수 없는 값은 버리고 그 까닭을 함께 돌려준다.
    /// 저장해 둔 덮어쓰기를 읽을 때 쓴다(토큰이 없어졌거나 파일을 손으로 고친 경우에도 앱이 켜져야 한다).
    public func applyingValid(
        _ overrides: ThemeOverrides
    ) -> (tokens: ThemeTokens, accepted: ThemeOverrides, rejected: [ThemeError]) {
        if let tokens = try? applying(overrides) { return (tokens, overrides, []) }
        var tokens = self
        var accepted = ThemeOverrides()
        var rejected: [ThemeError] = []
        for (key, value) in overrides.values.sorted(by: { $0.key < $1.key }) {
            let candidate = accepted.setting(key, to: value)
            do {
                tokens = try applying(candidate)
                accepted = candidate
            } catch let error as ThemeError {
                rejected.append(error)
            } catch {
                rejected.append(.invalidValue(key: key, value: value))
            }
        }
        return (tokens, accepted, rejected)
    }

    // MARK: - 접근자

    public func color(_ token: ColorToken, _ appearance: ThemeAppearance) -> RGBA {
        colors[appearance]![token]!
    }

    public func foreground(_ token: ColorToken, _ appearance: ThemeAppearance, on background: ColorToken) -> RGBA {
        let ink = color(token, appearance)
        guard appearance == .dark, token == .text2 || token == .text3 else { return ink }
        let base = color(.surface, appearance)
        let overlay = color(background, appearance)
        return ink.readable(on: base.mixed(with: overlay, fraction: overlay.alpha))
    }

    public func shadow(_ token: ShadowToken, _ appearance: ThemeAppearance) -> [ShadowLayer] {
        shadows[appearance]![token]!
    }

    public func textStyle(_ style: TextStyle) -> TextStyleSpec { textStyles[style]! }
    public func fontFamilies(_ role: FontRole) -> [String] { fontFamilies[role]! }
    public func space(_ token: SpaceToken) -> CGFloat { spaces[token]! }
    public func shape(_ token: ShapeToken) -> CGFloat { shapes[token]! }
    public func component(_ token: ComponentToken) -> CGFloat { components[token]! }
    /// 0~1 사이의 몫.
    public func ratio(_ token: RatioToken) -> Double { ratios[token]! }
    /// 1 이상의 개수.
    public func count(_ token: CountToken) -> Int { counts[token]! }

    /// SF Symbols 아이콘 하나의 크기 보정(`tokens.json`의 `iconOptical`). 눈으로 커 보이는 아이콘을 이웃과 같은
    /// 크기로 줄이는 값이다(0보다 크고 1 이하. 키우는 값은 받지 않는다). 적혀 있지 않으면 1.
    public func symbolScale(_ name: String) -> CGFloat { symbolScales[name] ?? 1 }

    public func paletteColor(id: String) -> PaletteColor? {
        palette.first { $0.id == id }
    }

    /// 노트 바탕색. `surface`에 팔레트 색을 `tint-mix`만큼 섞는다. 키가 없거나 모르는 키면 `surface`.
    public func noteBackground(paletteID: String?, _ appearance: ThemeAppearance) -> RGBA {
        let surface = color(.surface, appearance)
        guard let paletteID, let tint = paletteColor(id: paletteID) else { return surface }
        return surface.mixed(with: tint.color, fraction: material.tintMix)
    }

    /// 반투명 노트에 흰 데스크톱이 비칠 때를 상한으로 잡아 보조 글자를 고른다.
    public func noteForeground(_ token: ColorToken, paletteID: String?, appearance: ThemeAppearance,
                               overlay: ColorToken? = nil, selectable: Bool = false) -> RGBA {
        let ink = color(token, appearance)
        guard appearance == .dark, token == .text2 || token == .text3 else { return ink }
        var background = RGBA(red: 1, green: 1, blue: 1).mixed(with: color(.surface, .dark), fraction: material.opacity)
        if let paletteID, let tint = paletteColor(id: paletteID) {
            background = background.mixed(with: tint.color, fraction: material.tintMix)
        }
        if let overlay {
            let fill = color(overlay, .dark)
            background = background.mixed(with: fill, fraction: fill.alpha)
        }
        if selectable {
            let selected = color(.selected, .dark)
            if selected.luminance > background.luminance { background = selected }
        }
        return ink.readable(on: background)
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
            let size = try parse("type.\(keys.size)", TokenValueParser.size)
            let em = try keys.tracking.map { try parse("type.\($0)", TokenValueParser.em) } ?? 0
            textStyles[style] = TextStyleSpec(
                families: fontFamilies[keys.font]!,
                size: size,
                lineHeight: try parse("type.\(keys.lineHeight)", TokenValueParser.size),
                weight: CGFloat(try parse("type.\(keys.weight)", TokenValueParser.weight)),
                tracking: size * CGFloat(em)
            )
        }

        self.raw = raw
        self.colors = colors
        self.shadows = shadows
        self.fontFamilies = fontFamilies
        self.textStyles = textStyles
        self.spaces = try table("space", TokenValueParser.length)
        self.shapes = try table("shape", TokenValueParser.length)
        self.components = try table("component", TokenValueParser.length)
        self.ratios = try table("component", TokenValueParser.fraction)
        self.counts = try table("component", TokenValueParser.count)
        self.docPadding = try parse("component.doc-pad", TokenValueParser.insets)
        let scalePrefix = RawTokens.symbolScaleSection + "."
        var symbolScales: [String: CGFloat] = [:]
        for key in raw.values.keys where key.hasPrefix(scalePrefix) {
            let scale = try parse(key) { TokenValueParser.number($0).flatMap { $0 > 0 && $0 <= 1 ? $0 : nil } }
            symbolScales[String(key.dropFirst(scalePrefix.count))] = CGFloat(scale)
        }
        self.symbolScales = symbolScales
        self.material = MaterialTokens(
            opacity: try parse("material.opacity", TokenValueParser.unitNumber),
            blur: try parse("material.blur", TokenValueParser.length),
            tintMix: try parse("material.tint-mix", TokenValueParser.fraction),
            tintMixRow: try parse("material.tint-mix-row", TokenValueParser.fraction)
        )
        func motion<T>(_ token: MotionToken, _ parser: (String) -> T?) throws -> T {
            try parse("motion.\(token.rawValue)", parser)
        }
        facePeriods = try table("motion", TokenValueParser.seconds)
        self.motion = MotionTokens(
            duration: try motion(.duration, TokenValueParser.seconds),
            chevronRotation: try motion(.chevronRotation, TokenValueParser.seconds),
            curve: try motion(.ease, TokenValueParser.bezier),
            bell: BellMotion(
                period: try motion(.bellPeriod, TokenValueParser.seconds),
                rest: try motion(.bellRest, TokenValueParser.fraction),
                angles: try [MotionToken.bellAngle1, .bellAngle2, .bellAngle3].map {
                    try motion($0, TokenValueParser.degrees)
                },
                pivotFromTop: try motion(.bellPivot, TokenValueParser.fraction),
                curve: try motion(.bellEase, TokenValueParser.bezier)
            ),
            settingsFlash: try motion(.settingsFlash, TokenValueParser.seconds),
            caretBlink: try motion(.caretBlink, TokenValueParser.seconds),
            toastHold: try motion(.toastHold, TokenValueParser.seconds)
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
