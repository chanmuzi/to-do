import Testing
@testable import Theme

@Suite struct TokenValueParserTests {
    @Test func parsesLengthsAndNumbers() {
        #expect(TokenValueParser.points("12.5px") == 12.5)
        #expect(TokenValueParser.points("-12px") == -12)
        #expect(TokenValueParser.points("0") == 0)
        #expect(TokenValueParser.points("abc") == nil)
        #expect(TokenValueParser.number(".92") == 0.92)
        #expect(TokenValueParser.fraction("26%") == 0.26)
        #expect(TokenValueParser.seconds("180ms") == 0.18)
        #expect(TokenValueParser.em("-.02em") == -0.02)
        #expect(TokenValueParser.degrees("14deg") == 14)
        #expect(TokenValueParser.degrees("-12deg") == -12)
        #expect(TokenValueParser.degrees("14") == nil)
        #expect(TokenValueParser.degrees("720deg") == nil)
    }

    /// 수처럼 보이지만 값이 아닌 표기와 범위를 벗어난 값은 받지 않는다.
    @Test(arguments: ["nan", "inf", "-inf", "infinity", "0x10", "1e3", "+5", "1.2.3", "-", ".", "", "１２"])
    func rejectsNonDecimalNumbers(text: String) {
        #expect(TokenValueParser.number(text) == nil)
        #expect(TokenValueParser.points(text + "px") == nil)
        #expect(TokenValueParser.size(text + "px") == nil)
        #expect(TokenValueParser.seconds(text + "ms") == nil)
        #expect(TokenValueParser.fraction(text + "%") == nil)
    }

    @Test func rejectsOutOfRangeSizes() throws {
        #expect(TokenValueParser.size("13px") == 13)
        #expect(TokenValueParser.size("0") == nil)
        #expect(TokenValueParser.size("-13px") == nil)
        #expect(TokenValueParser.length("0") == 0)
        #expect(TokenValueParser.length("-4px") == nil)
        #expect(TokenValueParser.weight("650") == 650)
        #expect(TokenValueParser.weight("0") == nil)
        #expect(TokenValueParser.weight("1200") == nil)
        #expect(TokenValueParser.unitNumber("1.5") == nil)
        #expect(TokenValueParser.fraction("140%") == nil)
        #expect(TokenValueParser.seconds("-180ms") == nil)
        #expect(TokenValueParser.insets("10px -14px") == nil)
        #expect(TokenValueParser.color("rgba(300,0,0,1)") == nil)
        #expect(TokenValueParser.color("rgba(0,0,0,2)") == nil)
        #expect(TokenValueParser.shadow("0 4px -12px 0 rgba(0,0,0,.1)") == nil)

        let base = try ThemeTokens.bundled()
        for (key, value) in [
            ("type.fs-body", "nan"), ("type.fs-body", "inf"), ("type.fs-body", "-13px"),
            ("type.fs-body", "0x10"), ("type.lh-body", "0"), ("type.fw-body", "-400"),
            ("space.sp-1", "-4px"), ("material.opacity", "7"), ("material.blur", "-1px"),
        ] {
            #expect(throws: ThemeError.invalidValue(key: key, value: value)) {
                try base.applying(ThemeOverrides(values: [key: value]))
            }
        }
    }

    @Test func parsesColors() {
        #expect(TokenValueParser.color("#FFEB85") == RGBA(red: 1, green: 235 / 255, blue: 133 / 255))
        #expect(TokenValueParser.color("rgba(255,255,255,.11)") == RGBA(red: 1, green: 1, blue: 1, alpha: 0.11))
        #expect(TokenValueParser.color("rgb(0,0,0)") == RGBA(red: 0, green: 0, blue: 0))
        #expect(TokenValueParser.color("#12") == nil)
        #expect(TokenValueParser.color("red") == nil)
    }

    @Test func parsesCompoundValues() throws {
        let shadow = try #require(
            TokenValueParser.shadow("0 18px 44px -12px rgba(0,0,0,.28),0 4px 12px -2px rgba(0,0,0,.10)")
        )
        #expect(shadow.count == 2)
        #expect(shadow[0] == ShadowLayer(
            x: 0, y: 18, blur: 44, spread: -12, color: RGBA(red: 0, green: 0, blue: 0, alpha: 0.28)
        ))
        #expect(TokenValueParser.insets("10px 14px 18px")
            == ThemeInsets(top: 10, trailing: 14, bottom: 18, leading: 14))
        #expect(TokenValueParser.bezier("cubic-bezier(.25,.1,.25,1)")
            == BezierCurve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1))
        #expect(TokenValueParser.fontFamilies("\"Pretendard\",-apple-system,sans-serif")
            == ["Pretendard", "-apple-system", "sans-serif"])
    }
}
