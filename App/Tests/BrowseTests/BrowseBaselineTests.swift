import AppKit
import Testing
import Theme
import Models
@testable import Browse

@MainActor @Suite struct BrowseBaselineTests {
    @Test(arguments: ["", "회의 메모"])
    func mixedFontsShareBaselineAndHoverDoesNotMoveThem(title: String) throws {
        _ = FontRegistrar.registerBundledFonts()
        let theme = try Theme.bundled()
        let now = Date()
        let reminder = now.addingTimeInterval(86400)
        let view = BrowseNoteRowView(style: BrowseStyle(theme: theme), model: .init(
            row: BrowseNoteRow(id: NoteID(rawValue: "baseline"), spaceID: nil, title: title,
                preview: "내일 오후 3시 회의", previewHighlight: 0..<2, reminder: reminder, colorID: nil, isFloating: true),
            spaceSymbol: nil, spaceEmoji: nil, spaceName: nil,
            reminder: BrowseReminder(reminder: reminder, now: now, calendar: .current)))
        view.frame = NSRect(x: 0, y: 0, width: theme.component(.browseWidth), height: theme.component(.rowHeight))
        view.layoutSubtreeIfNeeded()
        let labels = view.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }
        #expect(labels.count == 3)
        let baselines = labels.map { $0.frame.minY + $0.firstBaselineOffsetFromTop }
        #expect(Set(baselines).count == 1)
        let frames = view.subviews.map(\.frame)
        for hovered in [true, false, true] {
            view.setHighlighted(hovered, animated: false)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            #expect(view.subviews.map(\.frame) == frames)
        }
    }
}
