import AppKit
import Testing
import Theme
@testable import NotePanel

@MainActor @Suite struct TitleFieldInputTests {
    private func withField(_ body: (TitleField, NSTextView) throws -> Void) throws {
        let field = TitleField(style: PanelStyle(theme: try Theme.bundled()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 28),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(field)
        field.frame = NSRect(x: 12, y: 6, width: 200, height: field.idealHeight)
        field.beginEditing(title: "제목")
        try body(field, #require(field.currentEditor() as? NSTextView))
    }

    @Test(arguments: ["insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:", "insertParagraphSeparator:"])
    func newlineCommandsFinishLikeReturn(command: String) throws {
        try withField { field, editor in
            var returns = 0
            var saved: [String] = []
            field.onReturn = { returns += 1 }
            field.onChange = { saved.append($0) }
            editor.doCommand(by: NSSelectorFromString(command))
            #expect(!field.isEditing)
            #expect(returns == 1)
            #expect(saved.last == "제목")
            #expect(field.stringValue == "제목")
        }
    }

    @Test(arguments: ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"])
    func multilineInputIsFlattenedBeforeReporting(separator: String) throws {
        try withField { field, editor in
            var saved: [String] = []
            field.onChange = { saved.append($0) }
            // 붙여넣기가 넘기는 여러 줄 replacement를 직접 넣는다. 클립보드는 쓰지 않는다.
            editor.insertText(NSAttributedString(string: "첫😀" + separator + "둘"),
                              replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            #expect(editor.string == "첫😀 둘")
            #expect(editor.selectedRange() == NSRange(location: 5, length: 0))
            #expect(saved.last == "첫😀 둘")
            #expect(saved.allSatisfy { $0.rangeOfCharacter(from: .newlines) == nil })
            field.endEditing()
            #expect(field.stringValue == "첫😀 둘")
            #expect(saved.last == "첫😀 둘")
        }
    }

    @Test func optionReturnKeyEventFinishesEditing() throws {
        try withField { field, editor in
            var returns = 0
            field.onReturn = { returns += 1 }
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .option, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: editor.window!.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            editor.keyDown(with: event)
            #expect(!field.isEditing)
            #expect(returns == 1)
            #expect(field.stringValue == "제목")
        }
    }

    @Test func markedTextIsUntouchedUntilCommit() throws {
        try withField { field, editor in
            var saved: [String] = []
            field.onChange = { saved.append($0) }
            editor.setMarkedText("한\n글", selectedRange: NSRange(location: 3, length: 0),
                                 replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            #expect(editor.hasMarkedText())
            #expect(editor.string == "한\n글")
            #expect(saved.isEmpty)
            editor.insertText("한\n글", replacementRange: editor.markedRange())
            #expect(!editor.hasMarkedText())
            #expect(editor.string == "한 글")
            #expect(saved.last == "한 글")
        }
    }

    @Test func endingCompositionAlsoFlattensTheFinalValue() throws {
        try withField { field, editor in
            var saved: [String] = []
            field.onChange = { saved.append($0) }
            editor.setMarkedText("한\n글", selectedRange: NSRange(location: 3, length: 0),
                                 replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            field.endEditing()
            #expect(saved.last == "한 글")
            #expect(field.stringValue == "한 글")
        }
    }
}

extension TitleFieldInputTests {
    @Test func emptyTitleKeepsFirstRectAfterTypingAndDeleting() throws {
        try withField { field, _ in
            field.endEditing()
            field.beginEditing(title: "")
            let view = try #require(field.currentEditor() as? NSTextView)
            func rect() -> NSRect {
                view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil)
            }
            let empty = rect()
            view.insertText("가", replacementRange: view.selectedRange())
            let typed = rect()
            #expect(typed.height > 0)
            #expect(empty.minY == typed.minY && empty.height == typed.height)
            view.deleteBackward(nil)
            #expect(view.string.isEmpty)
            #expect(rect().minY == typed.minY && rect().height == typed.height)
            field.endEditing()
            #expect(field.titleCursor == .arrow)
        }
    }

    @Test func markedTitleKeepsCompositionWithoutDecoration() throws {
        try withField { _, view in
            let position = view.selectedRange()
            let marked = NSAttributedString(string: "ㅎ", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.red, .backgroundColor: NSColor.green])
            view.setMarkedText(marked, selectedRange: NSRange(location: 1, length: 0), replacementRange: position)
            #expect(view.hasMarkedText())
            #expect(view.markedTextAttributes?[.underlineStyle] as? Int == 0)
            #expect(view.markedTextAttributes?[.foregroundColor] == nil)
            #expect(view.markedTextAttributes?[.backgroundColor] == nil)
            let stored = try #require(view.textStorage?.attributes(at: view.markedRange().location, effectiveRange: nil))
            #expect((stored[.underlineStyle] as? Int ?? 0) == 0)
            #expect(stored[.foregroundColor] as? NSColor != NSColor.red && stored[.backgroundColor] == nil)
            let drawn = view.layoutManager?.temporaryAttributes(atCharacterIndex: view.markedRange().location, effectiveRange: nil)
            #expect((drawn?[.underlineStyle] as? Int ?? 0) == 0)
            #expect(drawn?[.foregroundColor] == nil && drawn?[.backgroundColor] == nil)
            view.insertText("한", replacementRange: view.markedRange())
            #expect(view.string == "제목한" && !view.hasMarkedText())
        }
    }
}
