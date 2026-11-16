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

    func perform(_ action: EditorAction) {
        step { editor.perform(action) }
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
}
