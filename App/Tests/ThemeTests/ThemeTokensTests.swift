import Foundation
import Testing
@testable import Theme

@Suite struct ThemeTokensTests {
    let tokens: ThemeTokens
    /// 테스트가 직접 읽은 `tokens.json`. 접근자가 준 값과 견준다.
    let json: [String: Any]

    init() throws {
        tokens = try ThemeTokens.bundled()
        let data = try Data(contentsOf: ThemeResources.tokensURL())
        json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func section(_ path: String...) throws -> [String: String] {
        var node: Any = json
        for key in path { node = try #require((node as? [String: Any])?[key]) }
        return try #require(node as? [String: String])
    }

    @Test func bundledTokensAreTheRepositoryFile() throws {
        // 번들에 든 파일이 App/Resources/tokens.json과 같은 파일인지(심볼릭 링크가 살아 있는지) 본다.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/tokens.json")
        #expect(try Data(contentsOf: ThemeResources.tokensURL()) == Data(contentsOf: source))
    }

    @Test func lightAndDarkColorsMatchKnownValues() {
        #expect(tokens.color(.surface, .light) == RGBA(red: 1, green: 1, blue: 1))
        #expect(tokens.color(.surface, .dark) == RGBA(red: 30/255, green: 30/255, blue: 30/255))
        #expect(tokens.color(.text, .dark) == RGBA(red: 236 / 255, green: 236 / 255, blue: 236 / 255))
        #expect(tokens.color(.hover, .light) == RGBA(red: 96/255, green: 76/255, blue: 52/255, alpha: 0.08))
        #expect(tokens.color(.hover, .dark) == RGBA(red: 224/255, green: 208/255, blue: 186/255, alpha: 0.12))
        #expect(tokens.color(.formatActive, .light) == RGBA(red: 96/255, green: 76/255, blue: 52/255, alpha: 0.14))
        #expect(tokens.color(.formatActive, .dark) == RGBA(red: 224/255, green: 208/255, blue: 186/255, alpha: 0.16))
        #expect(tokens.color(.selected, .light) == RGBA(red: 222/255, green: 218/255, blue: 212/255))
        #expect(tokens.color(.selected, .dark) == RGBA(red: 70/255, green: 66/255, blue: 61/255))
        #expect(tokens.textStyle(.selected).weight == 500)
        #expect(tokens.textStyle(.row).weight == 450)
        #expect(tokens.textStyle(.body).weight == 400)
        #expect(tokens.color(.warn, .light) == RGBA(red: 229 / 255, green: 52 / 255, blue: 43 / 255))
        #expect(tokens.color(.warn, .dark) == RGBA(red: 1, green: 121 / 255, blue: 110 / 255))
        #expect(tokens.color(HighlightColor.yellow.background, .light)
            == RGBA(red: 1, green: 235 / 255, blue: 133 / 255))
        #expect(tokens.color(HighlightColor.blue.background, .dark)
            == RGBA(red: 110 / 255, green: 170 / 255, blue: 1, alpha: 0.28))
    }

    @Test(arguments: ThemeAppearance.allCases)
    func everyColorInTheFileIsExposedAndMatches(appearance: ThemeAppearance) throws {
        let colors = try section("color", appearance.rawValue)
        let shadowKeys = Set(ShadowToken.allCases.map(\.rawValue))
        let colorKeys = Set(colors.keys).subtracting(shadowKeys)
        // 파일의 색 키와 코드의 ColorToken이 정확히 같아야 한다(한쪽만 늘어나면 실패).
        #expect(colorKeys == Set(ColorToken.allCases.map(\.rawValue)))
        for token in ColorToken.allCases {
            let text = try #require(colors[token.rawValue])
            let expected = try #require(TokenValueParser.color(text))
            #expect(tokens.color(token, appearance) == expected, "\(token.rawValue)")
        }
        #expect(tokens.shadow(.window, appearance).count == 2)
        #expect(tokens.shadow(.pop, appearance).count == 2)
    }

    @Test func darkSecondaryTextMeetsContrastOnEveryLevel() {
        for surface in [ColorToken.surface, .surface2, .surface3, .selected] {
            let background = tokens.color(surface, .dark)
            for token in [ColorToken.text2, .text3] {
                let ink = tokens.foreground(token, .dark, on: surface)
                #expect((ink.luminance + 0.05) / (background.luminance + 0.05) >= 4.5)
                #expect(tokens.foreground(token, .light, on: surface) == tokens.color(token, .light))
            }
        }
    }

    @Test func metricsCoverTheFile() throws {
        #expect(Set(try section("space").keys) == Set(SpaceToken.allCases.map(\.rawValue)))
        #expect(Set(try section("shape").keys) == Set(ShapeToken.allCases.map(\.rawValue)))
        #expect(Set(try section("component").keys)
            == Set(ComponentToken.allCases.map(\.rawValue))
            .union(RatioToken.allCases.map(\.rawValue)).union(CountToken.allCases.map(\.rawValue))
            .union(["doc-pad"]))
        #expect(Set(try section("motion").keys) == Set(MotionToken.allCases.map(\.rawValue)).union(AgentFaceTiming.allCases.map(\.rawValue)))
        #expect(Set(try section("fonts").keys) == Set(FontRole.allCases.map(\.rawValue)))

        #expect(tokens.space(.sp4) == 16)
        #expect(tokens.shape(.windowRadius) == 10)
        #expect(tokens.shape(.chromeHeight) == TokenValueParser.length(try section("shape")["chrome-h"]!))
        #expect(tokens.component(.settingsNavSingleLineHoverHeight) == 30)
        #expect(tokens.component(.settingsNavTwoLineHoverInsetY) == 4)
        #expect(tokens.component(.caretWidth) == 1.5)
        #expect(tokens.component(.browseWidth) == 300)
        #expect(tokens.docPadding == TokenValueParser.insets(try section("component")["doc-pad"]!))
        #expect(tokens.material == MaterialTokens(opacity: 0.92, blur: 24, tintMix: 0.26, tintMixRow: 0.18))
        #expect(tokens.motion.duration == 0.18)
        #expect(tokens.motion.curve == BezierCurve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1))
    }

    /// 종 흔들림(spec 15)과 노트 높이 한도(spec 5.6)는 토큰에서 온다.
    @Test func bellMotionAndHeightLimitComeFromTheFile() {
        let bell = tokens.motion.bell
        #expect(bell.period == 1.6)
        #expect(bell.rest == 0.6)
        #expect(bell.angles == [14, -12, 6])
        #expect(bell.pivotFromTop == 0.12)
        #expect(bell.curve == BezierCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1))
        // 뒤 40%에서만 흔들린다: 60%까지 0도, 그 뒤 10%마다 14, -12, 6도, 끝에서 0도.
        let frames = bell.keyframes
        #expect(frames.map(\.degrees) == [0, 0, 14, -12, 6, 0])
        for (time, expected) in zip(frames.map(\.time), [0, 0.6, 0.7, 0.8, 0.9, 1]) {
            #expect(abs(time - expected) < 1e-9)
        }
        #expect(tokens.ratio(.noteMaxScreenHeight) == 0.7)
    }

    @Test func textStylesFollowTheTypeScale() throws {
        let type = try section("type")
        let body = tokens.textStyle(.body)
        #expect(body.families.first == "Pretendard")
        #expect(body.size == TokenValueParser.length(type["fs-body"]!))
        #expect(body.lineHeight == TokenValueParser.length(type["lh-body"]!))
        #expect(body.weight == 400)
        #expect(body.tracking == 0)

        let h1 = tokens.textStyle(.h1)
        #expect(h1.size == TokenValueParser.length(type["fs-h1"]!))
        #expect(Double(h1.weight) == (try #require(TokenValueParser.weight(type["fw-h1"]!))))
        #expect(abs(h1.tracking - (h1.size * CGFloat(TokenValueParser.em(type["ls-h1"]!)!))) < 0.0001)

        #expect(tokens.textStyle(.strong).weight == 650)
        #expect(tokens.textStyle(.row).size == TokenValueParser.length(type["fs-row"]!))
        #expect(tokens.textStyle(.micro).families.first == "D2Coding")
        #expect(tokens.textStyle(.code).size == TokenValueParser.length(type["fs-code"]!))
    }

    @Test func paletteAndAccentPresets() {
        #expect(tokens.palette.map(\.id) == (1...8).map { "tint-\($0)" })
        #expect(tokens.paletteColor(id: "tint-1")?.name == "안개")
        #expect(tokens.paletteColor(id: "tint-1")?.color
            == RGBA(red: 142 / 255, green: 154 / 255, blue: 175 / 255))
        #expect(tokens.accentPresets.count == 5)
        #expect(tokens.accentPresets[1].light == RGBA(red: 26 / 255, green: 143 / 255, blue: 76 / 255))
    }

    @Test func noteBackgroundMixesPaletteIntoSurface() throws {
        #expect(tokens.noteBackground(paletteID: nil, .light) == tokens.color(.surface, .light))
        #expect(tokens.noteBackground(paletteID: "없는-키", .dark) == tokens.color(.surface, .dark))

        let surface = tokens.color(.surface, .dark)
        let tint = try #require(tokens.paletteColor(id: "tint-2")).color
        let dark = tokens.noteBackground(paletteID: "tint-2", .dark)
        #expect(dark == surface.mixed(with: tint, fraction: tokens.material.tintMix))
        #expect(dark.alpha == 1)

        let row = try #require(tokens.rowTint(paletteID: "tint-2"))
        #expect(row.alpha == 0.18)
        #expect(tokens.rowTint(paletteID: nil) == nil)
    }

    @Test func rejectsBrokenDocuments() {
        #expect(throws: ThemeError.self) { try ThemeTokens(data: Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try ThemeTokens(data: Data("not json".utf8)) }
    }
}
