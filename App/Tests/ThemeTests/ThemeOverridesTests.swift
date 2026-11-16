import Foundation
import Testing
@testable import Theme

@Suite @MainActor struct ThemeOverridesTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("theme-overrides.json")
    }

    @Test func overridesLayerOnTopOfBaseTokens() throws {
        let base = try ThemeTokens.bundled()
        let overrides = ThemeOverrides()
            .setting(ThemeOverrides.key(.accent, .light), to: "#1A8F4C")
            .setting("type.fs-body", to: "15px")
            .setting("material.opacity", to: ".8")
            .setting("palette.tint-1", to: "#102030")
        let layered = try base.applying(overrides)

        #expect(layered.color(.accent, .light) == RGBA(red: 26 / 255, green: 143 / 255, blue: 76 / 255))
        #expect(layered.textStyle(.body).size == 15)
        #expect(layered.material.opacity == 0.8)
        #expect(layered.paletteColor(id: "tint-1")?.color == RGBA(red: 16 / 255, green: 32 / 255, blue: 48 / 255))
        // 덮어쓰지 않은 값과 다른 모양의 값은 그대로다.
        #expect(layered.color(.accent, .dark) == base.color(.accent, .dark))
        #expect(layered.color(.surface, .light) == base.color(.surface, .light))
        #expect(layered.textStyle(.h1) == base.textStyle(.h1))
        // 원본은 바뀌지 않는다.
        #expect(base.textStyle(.body).size == 13)
        // 덮어쓰기를 걷어 내면 원본과 같다.
        #expect(try base.applying(ThemeOverrides()) == base)
    }

    @Test func rejectsUnknownKeysAndBadValues() throws {
        let base = try ThemeTokens.bundled()
        #expect(throws: ThemeError.unknownOverrideKey("color.light.nope")) {
            try base.applying(ThemeOverrides(values: ["color.light.nope": "#000000"]))
        }
        #expect(throws: ThemeError.invalidValue(key: "color.light.accent", value: "green")) {
            try base.applying(ThemeOverrides(values: ["color.light.accent": "green"]))
        }
    }

    @Test func themePersistsOverridesAndKeepsStateOnFailure() throws {
        let store = ThemeOverrideStore(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

        let theme = try Theme.bundled(overrideStore: store, appearance: .dark)
        #expect(theme.overrides.isEmpty)
        #expect(theme.rgba(.accent) == RGBA(red: 1, green: 1, blue: 1))

        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Theme.didChangeNotification, object: theme, queue: nil
        ) { _ in MainActor.assumeIsolated { notifications += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }

        let overrides = ThemeOverrides().setting(ThemeOverrides.key(.accent, .dark), to: "#3DDC84")
        try theme.setOverrides(overrides)
        #expect(theme.rgba(.accent) == RGBA(red: 61 / 255, green: 220 / 255, blue: 132 / 255))
        #expect(notifications == 1)

        #expect(throws: ThemeError.self) {
            try theme.setOverrides(ThemeOverrides(values: ["type.fs-body": "큰 글씨"]))
        }
        #expect(theme.overrides == overrides)
        #expect(notifications == 1)

        // 다시 만든 테마가 저장된 덮어쓰기를 읽는다.
        let reloaded = try Theme.bundled(overrideStore: store, appearance: .dark)
        #expect(reloaded.overrides == overrides)
        #expect(reloaded.rgba(.accent) == theme.rgba(.accent))
    }

    @Test func dynamicColorsResolvePerAppearance() throws {
        let theme = try Theme.bundled()
        let color = theme.nsColor(.surface)
        func resolved(_ appearance: ThemeAppearance) throws -> [CGFloat] {
            var components: [CGFloat] = []
            try #require(appearance.nsAppearance).performAsCurrentDrawingAppearance {
                let srgb = color.usingColorSpace(.sRGB)!
                components = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            }
            return components
        }
        #expect(try resolved(.light) == [1, 1, 1])
        #expect(try resolved(.dark) == [0, 0, 0])
    }
}
