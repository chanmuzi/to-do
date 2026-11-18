import AppKit
import Testing
import Theme
import Models
@testable import Browse

@MainActor @Suite struct BrowseBaselineTests {
    @Test func resultTitleUsesRegularMenuFontExceptForTheMatch() throws {
        _ = FontRegistrar.registerBundledFonts()
        let theme = try Theme.bundled()
        let title = "회의 안건"
        let row = BrowseNoteRow(id: NoteID(rawValue: "font"), spaceID: nil, title: title,
                                preview: "", previewHighlight: nil, titleHighlight: 3..<5, isFloating: false)
        let view = BrowseNoteRowView(style: BrowseStyle(theme: theme), row: row, space: nil,
                                     directory: FileManager.default.temporaryDirectory)
        let label = try #require(view.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == title })
        let value = label.attributedStringValue
        let regular = try #require(value.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let matched = try #require(value.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        let menuFont = theme.nsFont(.body, size: theme.tokens.textStyle(.title).size)
        #expect(regular == menuFont && regular.familyName == "Pretendard Variable")
        #expect(regular.pointSize == 13 && matched.pointSize == 13)
        let weightAxis = 0x7767_6874
        // Core Text는 기본 굵기로 그릴 때 variation 사전에 그 축을 생략한다.
        let axes = try #require(CTFontCopyVariationAxes(regular) as? [[CFString: Any]])
        let axis = try #require(axes.first { $0[kCTFontVariationAxisIdentifierKey] as? Int == weightAxis })
        let regularWeight = (CTFontCopyVariation(regular) as? [Int: Double])?[weightAxis]
            ?? (axis[kCTFontVariationAxisDefaultValueKey] as? Double)
        #expect(regularWeight == 400)
        #expect((CTFontCopyVariation(matched) as? [Int: Double])?[weightAxis] == 600)
    }

    @Test(arguments: ["", "회의 메모"])
    func mixedFontsShareBaselineAndHoverDoesNotMoveThem(title: String) throws {
        _ = FontRegistrar.registerBundledFonts()
        let theme = try Theme.bundled()
        let row = BrowseNoteRow(id: NoteID(rawValue: "baseline"), spaceID: nil, title: title,
                                preview: "내일 오후 3시 회의", previewHighlight: 0..<2, titleHighlight: nil, isFloating: false)
        let view = BrowseNoteRowView(style: BrowseStyle(theme: theme), row: row, space: nil,
                                     directory: FileManager.default.temporaryDirectory)
        view.frame = NSRect(x: 0, y: 0, width: theme.component(.browseWidth), height: theme.component(.browseRowHeight))
        view.layoutSubtreeIfNeeded()
        let labels = view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }
        #expect(labels.count == 2)
        let baselines = labels.map { $0.frame.minY + $0.firstBaselineOffsetFromTop }
        #expect(Set(baselines).count == 1)
        let frames = view.subviews.map(\.frame)
        for hovered in [true, false, true] {
            view.setHighlighted(hovered, animated: false)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            #expect(view.pin.isHidden != hovered)
            #expect(view.subviews.map(\.frame) == frames)
        }
    }
}
