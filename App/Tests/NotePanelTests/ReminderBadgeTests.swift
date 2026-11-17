import AppKit
import Testing
import Models
import Theme
@testable import NotePanel

@MainActor @Suite struct ReminderBadgeTests {
    @Test(arguments: [false, true], [300.0, 3600.0])
    func onlyIconWithTimeHelpAndStableSize(event: Bool, seconds: Double) throws {
        let theme = try Theme.bundled()
        let badge = ReminderBadgeView(style: PanelStyle(theme: theme))
        let now = Date()
        let item = ScheduleItem(start: now.addingTimeInterval(seconds), end: event ? now.addingTimeInterval(seconds + 3600) : nil)
        let presentation = ReminderPresentation(item: item, now: now, options: NoteDisplayOptions(), calendar: .current)
        badge.apply(presentation, animated: false)
        badge.frame = NSRect(x: 0, y: 0, width: badge.fittingWidth!, height: theme.shape(.chromeHeight))
        badge.layoutSubtreeIfNeeded()
        #expect(badge.fittingWidth == theme.component(.iconButton))
        #expect(badge.subviews.allSatisfy { !($0 is NSTextField) })
        #expect(badge.toolTip == presentation.accessibilityLabel)
        #expect(badge.accessibilityLabel()?.contains(presentation.text!) == true)
        let icon = try #require(badge.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(icon.frame.width == theme.symbolFrame(NSRect(x: 0, y: 0, width: theme.component(.iconLarge), height: theme.component(.iconLarge))).width)
        #expect(icon.contentTintColor?.usingColorSpace(.deviceRGB) == theme.nsColor(seconds == 300 ? .warn : .text2).usingColorSpace(.deviceRGB))
        #expect(presentation.symbolName == (event ? "calendar" : seconds == 300 ? "bell" : "clock"))
        var presses = 0
        badge.onPress = { presses += 1 }
        #expect(badge.accessibilityPerformPress())
        #expect(presses == 1)
    }
}
