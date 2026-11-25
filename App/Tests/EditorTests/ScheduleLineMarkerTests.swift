import AppKit
import Models
import Testing
import Theme
@testable import Editor

@MainActor @Suite struct ScheduleLineMarkerTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func markers(_ note: Note, after seconds: TimeInterval = 0) -> [Int: ScheduleLineMarker] {
        ScheduleLineMarker.markers(in: note, now: now.addingTimeInterval(seconds), options: .init(), calendar: .current)
    }

    @Test func activeSourcesGroupByLineAndUseEarliestLead() throws {
        let source = InlineScheduleSource(line: 0, text: "약속")
        let reminder = ScheduleItem(start: now.addingTimeInterval(1200), imminentLeadMinutes: .ten, inlineSource: source)
        var event = reminder
        event.id = "event"
        event.start = now.addingTimeInterval(3000)
        event.end = event.start.addingTimeInterval(300)
        var note = Note(id: .make(), body: "약속", schedules: [event, reminder], created: now, modified: now)
        #expect(markers(note).count == 1)
        #expect(markers(note)[0]?.selectedID == nil)
        #expect(markers(note)[0]?.isImminent == false)
        #expect(markers(note, after: 600)[0]?.isImminent == true)
        #expect(markers(note, after: 1200)[0]?.isImminent == false)
        note.schedules[1].isCompleted = true
        #expect(markers(note)[0]?.selectedID == event.id)
        note.body = "새 줄\n약속"
        #expect(markers(note)[1]?.selectedID == event.id)
        note.schedules[0].isDeleted = true
        #expect(markers(note).isEmpty)
        for line: Int? in [nil, -1, 9, 0] {
            var stale = reminder
            stale.inlineSource?.line = line
            note.schedules = [stale]
            #expect(markers(note).isEmpty)
        }
    }

    @Test func firstFragmentAndStableGutterPreserveTextSelectionAndHeight() throws {
        let text = "+ 묶음\n\t[ ] " + String(repeating: "긴 본문 ", count: 12)
        let harness = try EditorHarness(text, width: 240)
        let editor = harness.editor
        editor.configuration.showsScheduleGutter = true
        editor.view.layoutSubtreeIfNeeded()
        let source = InlineScheduleSource(line: 1, text: text.components(separatedBy: "\n")[1])
        let item = ScheduleItem(start: now, inlineSource: source)
        let note = Note(id: .make(), body: text, schedules: [item], created: now, modified: now)
        let selection = NSRange(location: 2, length: 1)
        editor.selectedRange = selection
        let height = editor.contentHeight
        editor.setScheduleMarkers(markers(note))
        let controller = editor.controller
        let button = try #require(controller.scheduleButtons[1])
        let first = try #require(controller.textPoint(forLine: 1))
        let gutter = try #require(controller.gutterPoint(forLine: 1))
        #expect(button.frame.midY == first.y && button.frame.midY == gutter.y)
        #expect(button.frame.size == CGSize(width: 20, height: 20))
        #expect(controller.textView.textContainerOrigin.x + controller.textContainer.size.width == button.frame.minX)
        #expect(editor.contentHeight > harness.theme.lineHeight(.body) * 3)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == markers(note)[1]?.label)
        var opened: String?
        editor.onOpenSchedule = { id, _ in opened = id }
        button.openSchedule()
        #expect(opened == item.id)
        #expect(editor.contentHeight == height && editor.selectedRange == selection)
        #expect(controller.textView.textStorage?.string == text && editor.text == text)
        editor.foldedLines = [0]
        #expect(button.isHidden)
        editor.foldedLines = []
        #expect(!button.isHidden)
        editor.setScheduleMarkers([:])
        #expect(button.superview == nil && editor.contentHeight == height)
    }
}
