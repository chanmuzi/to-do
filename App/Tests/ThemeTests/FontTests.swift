import AppKit
import Testing
@testable import Theme

@Suite @MainActor struct FontTests {
    @Test func registersBundledFontsAndResolvesTextStyles() throws {
        let files = try FontRegistrar.registerBundledFonts()
        #expect(files.map(\.lastPathComponent) == ["D2Coding.ttf", "D2CodingBold.ttf", "PretendardVariable.ttf"])
        // 두 번 불러도 실패하지 않는다.
        try FontRegistrar.registerBundledFonts()

        let theme = try Theme.bundled()
        let body = theme.nsFont(.body)
        #expect(body.familyName?.hasPrefix("Pretendard") == true)
        #expect(body.pointSize == 13)

        let code = theme.nsFont(.code)
        #expect(code.familyName == "D2Coding")
        #expect(code.pointSize == 12)

        // 가변 글꼴의 굵기 축에 토큰 값이 그대로 들어간다.
        #expect(weightAxisValue(theme.nsFont(.strong)) == 650)
        #expect(weightAxisValue(theme.nsFont(.h1)) == 700)
        #expect(weightAxisValue(theme.nsFont(.body, weight: 500)) == 500)
        // 굵기별 파일이 따로 있는 글꼴은 굵은 파일로 바뀐다.
        #expect(theme.nsFont(.code, weight: 700).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!code.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func fallsBackWhenFamilyIsNotInstalled() {
        let font = FontResolver.font(families: ["없는 글꼴", "ui-monospace"], size: 12, weight: 400)
        #expect(font.isFixedPitch)
    }

    private func weightAxisValue(_ font: NSFont) -> Double? {
        let variation = CTFontCopyVariation(font) as? [Int: Double]
        return variation?[0x7767_6874]
    }
}
