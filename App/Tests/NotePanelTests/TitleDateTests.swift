import AppKit
import Testing
import Theme
import DateTime
@testable import NotePanel

@MainActor @Suite struct TitleDateTests {
    @Test(arguments: ["내일", "긴 회의 제목 내일 오후 3시~4시"])
    func previewHasItsOwnSpaceAboveTitleAndBody(source: String) throws {
        let theme = try Theme.bundled()
        let body = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 100))
        body.string = "본문 첫 줄은 가리지 않습니다\n본문 둘째 줄도 그대로입니다"
        let root = NoteRootView(style: PanelStyle(theme: theme), bodyView: body)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        let field = try #require(root.topRow.subviews.compactMap { $0 as? TitleField }.first)
        field.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
        field.beginEditing(title: source)
        field.updateDateSuggestion()
        root.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        let preview = root.convert(field.dateHint.bounds, from: field.dateHint)
        let editor = try #require(field.currentEditor() as? NSTextView)
        let titleScreen = editor.firstRect(forCharacterRange: NSRange(location: 0, length: editor.string.utf16.count), actualRange: nil)
        let title = root.convert(window.convertFromScreen(titleScreen), from: nil)
        let bodyRect = root.convert(body.bounds, from: body)
        #expect(!field.dateHint.isHidden)
        #expect(!preview.intersects(title))
        #expect(!preview.intersects(bodyRect))
        #expect(root.bounds.contains(preview))
        #expect(body.string == "본문 첫 줄은 가리지 않습니다\n본문 둘째 줄도 그대로입니다")
        field.hideDateSuggestion()
        root.layoutSubtreeIfNeeded()
        #expect(root.topRow.datePreviewHeight == 0)
        #expect(root.chromeHeight == theme.shape(.chromeHeight) + theme.shape(.borderWidth))
    }

    @Test(arguments: ["회의 내일 3시 다음 안건", "😀 회의 내일 다음 😀 안건", "내일 3시 다음 안건", "회의 내일   다음 안건"])
    func acceptanceAndRedoMoveCaretBackByDeletedUTF16Length(source: String) throws {
        try withField(source) { field, editor in
            field.onAcceptDate = { _ in InlineDateEffect(undo: {}, redo: {}) }
            let token = source.contains("3시") ? "3시" : "내일"
            let before = NSRange(location: (source as NSString).range(of: token).upperBound, length: 0)
            editor.setSelectedRange(before)
            field.updateDateSuggestion()
            #expect(field.dateSuggestion != nil)
            let undo = try #require(editor.undoManager)
            undo.groupsByEvent = false
            editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            let accepted = editor.string
            let expected = before.location - (source.utf16.count - accepted.utf16.count)
            #expect(editor.selectedRange() == NSRange(location: max(0, expected), length: 0))
            #expect(editor.selectedRange().location < accepted.utf16.count)
            #expect(accepted.hasSuffix("안건"))
            undo.undo()
            #expect(editor.string == source)
            #expect(editor.selectedRange() == before)
            undo.redo()
            #expect(editor.string == accepted)
            #expect(editor.selectedRange() == NSRange(location: max(0, expected), length: 0))
        }
    }

    @Test(arguments: ["회의 내일 3시", "회의 내일 3시~4시", "회의 내일", "😀 회의 내일 3시"])
    func tabUndoRedoIsOneStep(source: String) throws {
        try withField(source) { field, editor in
            var count = 0
            var last = ""
            field.onChange = { last = $0 }
            field.onAcceptDate = { request in
                #expect(request.source.line == nil && request.todo == nil)
                count += 1
                return InlineDateEffect(undo: { count -= 1 }, redo: { count += 1 })
            }
            field.updateDateSuggestion()
            #expect(field.dateSuggestion != nil)
            let undo = try #require(editor.undoManager)
            // 테스트는 런 루프 대신 묶음을 직접 닫는다.
            undo.groupsByEvent = false
            editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            #expect(count == 1)
            #expect(editor.string == (source.hasPrefix("😀") ? "😀 회의" : "회의"))
            #expect(last == editor.string)
            #expect(field.isEditing)
            undo.undo()
            #expect(editor.string == source)
            #expect(last == source)
            #expect(count == 0)
            undo.redo()
            #expect(count == 1)
            #expect(!editor.string.contains("내일"))
        }
    }
    @Test func escapeOnlyDismissesSuggestionAndCompositionNeverAccepts() throws {
        try withField("회의 내일 3시") { field, editor in
            var count = 0
            field.onAcceptDate = { _ in count += 1; return InlineDateEffect(undo: {}, redo: {}) }
            field.updateDateSuggestion()
            editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            #expect(field.isEditing)
            #expect(field.dateSuggestion == nil)
            #expect(editor.string == "회의 내일 3시")
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.setMarkedText("간", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
            field.updateDateSuggestion()
            #expect(field.dateSuggestion == nil)
            #expect(!field.acceptDateSuggestion(in: editor))
            editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            #expect(count == 0)
            #expect(editor.hasMarkedText())
            #expect(editor.string == "회의 내일 3시간")
        }
    }
    @Test func typingAfterAcceptanceHasItsOwnUndoStep() throws {
        try withField("회의 내일 3시") { field, editor in
            var count = 0
            field.onAcceptDate = { _ in count += 1; return InlineDateEffect(undo: { count -= 1 }, redo: { count += 1 }) }
            field.updateDateSuggestion()
            let undo = try #require(editor.undoManager)
            undo.groupsByEvent = false
            editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            undo.beginUndoGrouping()
            editor.insertText("!", replacementRange: editor.selectedRange())
            undo.endUndoGrouping()
            #expect(editor.string == "회의!")
            undo.undo()
            #expect(editor.string == "회의" && count == 1)
            undo.undo()
            #expect(editor.string == "회의 내일 3시" && count == 0)
        }
    }

    private func withField(_ title: String, _ body: (TitleField, NSTextView) throws -> Void) throws {
        let field = TitleField(style: PanelStyle(theme: try Theme.bundled()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(field)
        field.frame = NSRect(x: 12, y: 100, width: 300, height: field.idealHeight)
        field.beginEditing(title: title)
        try body(field, #require(field.currentEditor() as? NSTextView))
    }
}
