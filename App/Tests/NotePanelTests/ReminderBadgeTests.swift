import AppKit
import Testing
import Models
import Theme
@testable import NotePanel

@MainActor @Suite struct ReminderBadgeTests {
    @Test(arguments: [false, true], [300.0, 3600.0])
    func chipShowsTimeAndAdditionalCount(event: Bool, seconds: Double) throws {
        let theme = try Theme.bundled()
        let badge = ReminderBadgeView(style: PanelStyle(theme: theme))
        let now = Date()
        let item = ScheduleItem(start: now.addingTimeInterval(seconds), end: event ? now.addingTimeInterval(seconds + 3600) : nil)
        let presentation = ReminderPresentation(item: item, now: now, options: NoteDisplayOptions(), calendar: .current)
        badge.apply(presentation, count: 2, animated: false)
        badge.frame = NSRect(x: 0, y: 0, width: badge.fittingWidth!, height: theme.component(.iconButton))
        badge.layoutSubtreeIfNeeded()
        let chip = try #require(badge.subviews.first)
        #expect(chip.frame.height == theme.component(.badgeHeight))
        for component in badge.subviews { #expect(component.frame.midY == badge.bounds.midY) }
        let field = try #require(badge.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(field.font?.familyName == theme.nsFont(.body).familyName)
        #expect(field.font?.pointSize == theme.tokens.textStyle(.micro).size)
        let font = try #require(field.font)
        let widths = (0...9).map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
        #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.01)
        let labels = badge.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels == [presentation.text ?? "", "+2"])
        #expect(badge.toolTip == presentation.accessibilityLabel + " +2")
        #expect((badge.fittingWidth ?? 0) > theme.component(.iconButton))
        var presses = 0
        badge.onPress = { presses += 1 }
        #expect(badge.accessibilityPerformPress())
        #expect(presses == 1)
    }
}
