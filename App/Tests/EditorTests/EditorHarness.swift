import AppKit
import Testing
import Theme
@testable import Editor

/// 편집기를 화면에 띄우지 않는 창에 넣고, 실제 입력 경로(`insertText`, `doCommand(by:)`)로 다룬다.
@MainActor
final class EditorHarness {
    let theme: Theme
    let editor: MarkdownEditor
    let window: NSWindow
    private(set) var changes: [String] = []
    private(set) var heights: [CGFloat] = []
    private(set) var foldChanges: [Set<Int>] = []

    init(_ text: String = "", width: CGFloat = 340, checkbox: CheckboxStyle = .box) throws {
        theme = try Theme.bundled()
        editor = MarkdownEditor(theme: theme, configuration: MarkdownEditorConfiguration(checkboxStyle: checkbox))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = editor.view
        editor.text = text
        // 창이 키 창이 될 수 없는 테스트 환경에서도 편집 중인 모양을 본다.
        editor.controller.forcesActiveAppearance = true
        editor.focus()
        editor.onTextChange = { [weak self] in self?.changes.append($0) }
        editor.onContentHeightChange = { [weak self] in self?.heights.append($0) }
        editor.onFoldChange = { [weak self] in self?.foldChanges.append($0) }
        // 테스트에서는 런 루프가 돌지 않으므로 되돌리기 묶음을 단계마다 직접 닫는다.
        editor.undoManager.groupsByEvent = false
    }

    var controller: EditorController { editor.controller }
    var view: EditorTextView { controller.textView }
    var document: MarkdownDocument { controller.document }

    /// 되돌리기 한 단계로 묶어 실행한다.
    func step(_ body: () -> Void) {
        editor.undoManager.beginUndoGrouping()
        body()
        editor.undoManager.endUndoGrouping()
    }

    func type(_ text: String) {
        for character in text {
            step { view.insertText(String(character), replacementRange: view.selectedRange()) }
        }
    }

    func press(_ selector: Selector) {
        step { view.doCommand(by: selector) }
    }

    func press(_ selector: Selector, times: Int) {
        for _ in 0..<times { press(selector) }
    }

    func caret(at location: Int) {
        editor.selectedRange = NSRange(location: location, length: 0)
    }

    /// 한글 조합 중인 글자를 넣는다(입력기가 부르는 것과 같은 경로).
    func mark(_ text: String) {
        let range = view.hasMarkedText() ? view.markedRange() : view.selectedRange()
        step { view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: range) }
    }

    /// 조합을 확정한다.
    func commit(_ text: String) {
        step { view.insertText(text, replacementRange: view.markedRange()) }
    }

    func undo() {
        editor.undoManager.undo()
    }

    func redo() {
        editor.undoManager.redo()
    }

    func perform(_ action: EditorAction) {
        step { editor.perform(action) }
    }

    /// 원문에 커서(선택)를 `|`로 적어 넣은 것. 단계마다 원문과 커서를 한 번에 견준다.
    var marked: String {
        Scenario.marked(editor.text, selection: editor.selectedRange)
    }

    /// 커서를 그 원문 위치에 그대로 둔다(감춘 기호 옆의 어느 쪽인지까지 정해야 할 때).
    func place(at location: Int, length: Int = 0) {
        controller.setSelection(NSRange(location: location, length: length))
    }

    /// 키 이벤트를 만들어 단축키 경로(`performKeyEquivalent`)에 넣는다.
    @discardableResult
    func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        ) else { return false }
        // 선택 없이 누른 서식 단축키는 원문을 고치지 않는다(다음에 칠 글자의 서식만 정한다).
        // 되돌리기에 빈 단계가 끼지 않게 묶음을 열지 않는다.
        typealias Key = EditorShortcuts.Key
        let leavesTheSourceAlone = code == Key.l
            || (editor.selectedRange.length == 0 && [Key.b, Key.e, Key.x, Key.h].contains(code))
        guard !leavesTheSourceAlone else { return view.performKeyEquivalent(with: event) }
        var handled = false
        step { handled = view.performKeyEquivalent(with: event) }
        return handled
    }

    func caret(atEndOfLine line: Int) {
        editor.selectedRange = NSRange(location: document.lines[line].end, length: 0)
    }

    /// 그 줄이 화면에 보이는 문단(원문에 속성을 얹은 것).
    func display(line: Int) throws -> NSAttributedString {
        let range = document.lines[line].fullRange
        let paragraph = try #require(controller.textContentStorage(controller.contentStorage, textParagraphWith: range))
        return paragraph.attributedString
    }

    /// 문단 안에서 그 글자(문서 기준 범위)의 글꼴 크기.
    func fontSize(line: Int, at range: NSRange) throws -> [CGFloat] {
        let paragraph = try display(line: line)
        let start = document.lines[line].start
        return (range.location..<NSMaxRange(range)).map { index in
            (paragraph.attribute(.font, at: index - start, effectiveRange: nil) as? NSFont)?.pointSize ?? -1
        }
    }

    func color(line: Int, at location: Int) throws -> NSColor? {
        let paragraph = try display(line: line)
        return paragraph.attribute(.foregroundColor, at: location - document.lines[line].start, effectiveRange: nil) as? NSColor
    }
}

extension NSResponder {
    static let tab = #selector(NSResponder.insertTab(_:))
    static let backtab = #selector(NSResponder.insertBacktab(_:))
    static let newline = #selector(NSResponder.insertNewline(_:))
    static let backspace = #selector(NSResponder.deleteBackward(_:))
    static let forwardDelete = #selector(NSResponder.deleteForward(_:))
    static let left = #selector(NSResponder.moveLeft(_:))
    static let right = #selector(NSResponder.moveRight(_:))
    static let up = #selector(NSResponder.moveUp(_:))
    static let down = #selector(NSResponder.moveDown(_:))
    static let home = #selector(NSResponder.moveToBeginningOfLine(_:))
    static let end = #selector(NSResponder.moveToEndOfLine(_:))
    static let wordLeft = #selector(NSResponder.moveWordLeft(_:))
    static let wordRight = #selector(NSResponder.moveWordRight(_:))
    static let shiftRight = #selector(NSResponder.moveRightAndModifySelection(_:))
    static let shiftLeft = #selector(NSResponder.moveLeftAndModifySelection(_:))
    static let shiftDown = #selector(NSResponder.moveDownAndModifySelection(_:))
    static let shiftUp = #selector(NSResponder.moveUpAndModifySelection(_:))
}
