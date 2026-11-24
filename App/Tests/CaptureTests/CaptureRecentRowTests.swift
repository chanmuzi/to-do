import SwiftUI
import Testing
import Theme
@testable import Capture

@MainActor struct CaptureRecentRowTests {
    @Test func recentRowUsesCaptureInputTypefaceAtPreviewAndElapsedSizes() throws {
        FontRegistrar.registerBundledFonts()
        let theme = try Theme.bundled()
        let recent = CaptureRecentRequest(id: UUID(), question: "오늘 할 일?", detail: "회의 준비",
                                          date: Date(), face: .done)
        let row = CaptureRecentRow(theme: theme, recent: recent, open: {})
        let input = CaptureStyle(theme: theme).inputFont
        let context = EnvironmentValues().fontResolutionContext
        for (font, size) in [(row.previewFont, CGFloat(13)), (row.elapsedFont, CGFloat(12))] {
            let resolved = font.resolve(in: context).ctFont
            #expect(CTFontCopyPostScriptName(resolved) as String == input.fontName)
            #expect(CTFontGetSize(resolved) == size)
            #expect(!CTFontGetSymbolicTraits(resolved).contains(.traitMonoSpace))
        }
    }
}
