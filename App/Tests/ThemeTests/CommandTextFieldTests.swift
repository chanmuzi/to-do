import AppKit
import SwiftUI
import Testing
@testable import Theme

@Suite(.serialized) @MainActor struct CommandTextFieldTests {
    @Test func editableFieldOwnsReturnArrowsAndEscapeWithoutFocusRing() throws {
        _ = NSApplication.shared
        let theme = try Theme.bundled()
        var text = "내일 2pm", commands: [String] = []
        let root = NSHostingView(rootView: CommandTextField(text: Binding(get: { text }, set: { text = $0 }),
            theme: theme, placeholder: "예정 입력", ranges: [NSRange(location: 0, length: 6)],
            submit: { commands.append("return") }, cancel: { commands.append("escape") }, move: { commands.append("move:\($0)") }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        defer { window.close() }
        root.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let field = try #require(descendants(root).compactMap { $0 as? NSTextField }.first)
        #expect(field.isEditable && field.isSelectable && field.focusRingType == .none)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(commands == ["move:1", "move:-1", "return", "escape"])
        #expect(text == "내일 2pm")
    }
}
