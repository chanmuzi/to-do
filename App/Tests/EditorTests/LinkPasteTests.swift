import AppKit
import Testing
@testable import Editor

@Suite @MainActor struct LinkPasteTests {
    @Test(arguments: ["https://example.com", "http://example.com/p", "mailto:reader@example.com"])
    func selectedLabelSurvivesURLPasteAndSingleUndo(address: String) throws {
        let h = try EditorHarness.at("오늘 |검토할 글| 끝")
        h.paste(address)
        #expect(h.editor.text == "오늘 [검토할 글](\(address)) 끝")
        h.undo()
        #expect(h.marked == "오늘 |검토할 글| 끝")
    }

    @Test func pasteInsideCodeAndLinkReplacesOnlyTheSelectedText() throws {
        let url = "https://example.com"
        for (marked, expected) in [
            ("[ab|cd|ef](https://old.example)", "[ab" + url + "ef](https://old.example)"),
            ("`|code|`", "`" + url + "`"),
            ("```\n|code|\n```", "```\n" + url + "\n```"),
        ] {
            let h = try EditorHarness.at(marked)
            h.paste(url)
            #expect(h.editor.text == expected)
            h.undo()
            #expect(h.marked == marked)
        }
    }

    @Test func overlappingLinksKeepTextAndExplainUnavailableCommand() throws {
        let h = try EditorHarness.at("|앞 [글|자](https://old.example)")
        let initial = h.marked
        let item = NSMenuItem(title: "", action: MarkdownEditor.editLinkAction, keyEquivalent: "")
        #expect(!h.view.validateUserInterfaceItem(item) && item.toolTip != nil)
        h.perform(.link)
        h.paste("https://example.com")
        #expect(h.marked == initial && h.beeps == 2)
    }

    @Test func menuAddsThenEditsTheSameLinkAndRejectsAnUnsupportedAddress() throws {
        let h = try EditorHarness.at("|문서 [초안]|")
        let item = NSMenuItem(title: "", action: MarkdownEditor.editLinkAction, keyEquivalent: "")
        #expect(h.view.validateUserInterfaceItem(item) && item.title == "링크 추가")
        h.view.editMarkdownLink(item)
        h.controller.commitLink("file:///local")
        #expect(!h.controller.linkField.isHidden && h.beeps == 1)
        h.step { h.controller.commitLink("https://example.com") }
        #expect(h.view.validateUserInterfaceItem(item) && item.title == "링크 고치기")
        h.view.editMarkdownLink(item)
        #expect(h.controller.linkField.address == "https://example.com")
    }

    @Test func bareWebAddressIsClickableAndBareMailRemainsText() throws {
        for url in ["http://example.com", "https://example.com", "mailto:r@example.com"] {
            let h = try EditorHarness.at("|")
            h.paste(url)
            #expect(h.editor.text == url)
            let rect = try #require(h.controller.segmentRects(for: NSRange(location: 1, length: 1)).first)
            var opened: URL?
            h.editor.onOpenLink = { opened = $0 }
            let handled = h.controller.handleMouseDown(at: CGPoint(x: rect.midX, y: rect.midY))
            #expect(handled == !url.hasPrefix("mailto:"))
            #expect(opened?.absoluteString == (handled ? url : nil))
        }
    }

    @Test func contextMenuUsesTheBodySelection() throws {
        let h = try EditorHarness.at("|링크 글자|")
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: h.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        let menu = try #require(h.view.menu(for: event))
        let item = try #require(menu.item(withTitle: "링크 추가"))
        #expect(item.target === h.view && item.action == MarkdownEditor.editLinkAction && item.isEnabled)
        menu.performActionForItem(at: menu.index(of: item))
        #expect(!h.controller.linkField.isHidden)
    }
}
