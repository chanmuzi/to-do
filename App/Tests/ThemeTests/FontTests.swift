import AppKit
import Testing
@testable import Theme

@Suite @MainActor struct FontTests {
    @Test func registersBundledFontsAndResolvesTextStyles() throws {
        let registration = FontRegistrar.registerBundledFonts()
        #expect(registration.registered.map(\.lastPathComponent)
            == ["D2Coding.ttf", "D2CodingBold.ttf", "PretendardVariable.ttf"])
        #expect(registration.problems.isEmpty)
        // 두 번 불러도 실패하지 않는다.
        #expect(FontRegistrar.registerBundledFonts() == registration)

        let theme = try Theme.bundled()
        let body = theme.nsFont(.body)
        #expect(body.familyName?.hasPrefix("Pretendard") == true)
        #expect(body.pointSize == 13)

        let code = theme.nsFont(.code)
        #expect(code.familyName == "D2Coding")
        #expect(code.pointSize == 11.5)

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

    /// 글꼴 하나를 등록하지 못해도 던지지 않는다. 문제를 적어 돌려주고, 글꼴 고르기는 시스템 글꼴로 넘어간다.
    @Test func unregisterableFontIsReportedAndFallsBackToSystemFont() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("font-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("글꼴이 아님".utf8).write(to: directory.appendingPathComponent("Broken.ttf"))

        let registration = FontRegistrar.registerFonts(in: directory)
        #expect(registration.registered.isEmpty)
        #expect(registration.problems.count == 1)
        #expect(registration.problems.first?.contains("Broken.ttf") == true)
        #expect(FontRegistrar.registerFonts(in: directory.appendingPathComponent("없음")).problems.count == 1)

        let font = FontResolver.font(families: ["Broken", "-apple-system"], size: 13, weight: 400)
        #expect(font.pointSize == 13)
        #expect(font.familyName == NSFont.systemFont(ofSize: 13).familyName)
    }

    /// 번들의 가변 글꼴(`<가족> Variable`)을 같은 이름의 굵기별 글꼴보다 먼저 찾는다.
    @Test func prefersTheVariableFamily() {
        #expect(FontResolver.familyCandidates("Pretendard") == ["Pretendard Variable", "Pretendard"])
        FontRegistrar.registerBundledFonts()
        let font = FontResolver.font(families: ["Pretendard"], size: 13, weight: 500)
        #expect(font.familyName == "Pretendard Variable")
        #expect(weightAxisValue(font) == 500)
    }

    /// 굵기별 파일이 여럿인 가족은 보통·굵게 둘만이 아니라 가장 가까운 굵기를 고른다.
    @Test func staticFamiliesResolveTheClosestWeight() throws {
        try #require(NSFontManager.shared.availableMembers(ofFontFamily: "Helvetica Neue") != nil)
        func name(_ weight: CGFloat) -> String {
            FontResolver.font(families: ["Helvetica Neue"], size: 12, weight: weight).fontName
        }
        #expect(name(300) == "HelveticaNeue-Light")
        #expect(name(400) == "HelveticaNeue")
        #expect(name(500) == "HelveticaNeue-Medium")
        #expect(name(700) == "HelveticaNeue-Bold")
    }

    private func weightAxisValue(_ font: NSFont) -> Double? {
        let variation = CTFontCopyVariation(font) as? [Int: Double]
        return variation?[0x7767_6874]
    }
}
