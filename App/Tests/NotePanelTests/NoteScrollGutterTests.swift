import AppKit
import Models
import Testing
@testable import NotePanel

@MainActor @Suite struct NoteScrollGutterTests {
    @Test func overlayNeedsUserScrollAndLegacyTracksOverflow() {
        let scroll = NoteBodyScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        scroll.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 240))
        for style: NSScroller.Style in [.overlay, .legacy] {
            scroll.scrollerStyle = style
            scroll.update(contentHeight: 240, fittingHeight: true)
            scroll.beginUserScroll()
            #expect(!scroll.hasVerticalScroller)
            scroll.update(contentHeight: 120, fittingHeight: false)
            #expect(!scroll.hasVerticalScroller)
            scroll.update(contentHeight: 240, fittingHeight: false)
            #expect(scroll.hasVerticalScroller == (style == .legacy))
            scroll.beginUserScroll()
            #expect(scroll.hasVerticalScroller)
            #expect(scroll.verticalScroller?.controlSize == .small)
            scroll.endUserScroll(Notification(name: NSText.didChangeNotification))
            #expect(scroll.hasVerticalScroller == (style == .legacy))
            scroll.update(contentHeight: 120, fittingHeight: false)
            #expect(!scroll.hasVerticalScroller)
        }
    }

    @Test func retargetsTheRunningAnimationFromTheDisplayedHeight() async throws {
        let fixture = try NotePanelFixture()
        let panel = try fixture.makeCoordinator()
        defer { fixture.cleanUp(panel) }
        panel.displayOptions.heightMode = .fitContent
        let note = try fixture.notes.create(NoteDraft())
        try panel.open(note.id, focus: false)
        let controller = try #require(panel.controllers[note.id])
        let initial = controller.panel.frame
        controller.editor.text = Array(repeating: "본문", count: 9).joined(separator: "\n")
        let task = controller.heightAnimation
        if fixture.animates {
            #expect(await fixture.wait { controller.panel.frame.height > initial.height })
        }
        let displayed = controller.panel.frame.height
        controller.editor.text = Array(repeating: "본문", count: 11).joined(separator: "\n")
        let target = controller.contentHeight + controller.root.chromeHeight
        if fixture.animates {
            #expect(task != nil && task == controller.heightAnimation)
            #expect(controller.heightTransition?.from == displayed)
            #expect(controller.heightTarget == target)
            #expect(!controller.root.scrollView.hasVerticalScroller)
            await task?.value
        }
        #expect(controller.heightTarget == nil)
        #expect(controller.panel.frame.height == target)
        #expect(controller.panel.frame.maxY == initial.maxY)
        #expect(!controller.root.scrollView.hasVerticalScroller)
    }

    @Test func lastCaretLineStaysVisibleWhileTheWindowGrows() async throws {
        let fixture = try NotePanelFixture()
        let panel = try fixture.makeCoordinator()
        defer { fixture.cleanUp(panel) }
        panel.displayOptions.heightMode = .fitContent
        let note = try fixture.notes.create(NoteDraft())
        try panel.open(note.id, focus: false)
        let controller = try #require(panel.controllers[note.id])
        let text = try #require(controller.editor.view as? NSTextView)
        let layout = try #require(text.layoutManager)
        let scroll = controller.root.scrollView
        try #require(controller.panel.makeFirstResponder(text))
        controller.editor.text = Array(repeating: "마지막 줄", count: 10).joined(separator: "\n")
        let end = text.string.utf16.count
        text.setSelectedRange(NSRange(location: end, length: 0))
        text.scrollRangeToVisible(text.selectedRange())
        let glyph = layout.glyphIndexForCharacter(at: end - 1)
        let line = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        let settled = await fixture.wait {
            controller.root.layoutSubtreeIfNeeded()
            #expect(scroll.documentVisibleRect.contains(line))
            #expect(!scroll.hasVerticalScroller)
            return controller.heightTarget == nil
        }
        #expect(settled)
    }
}
