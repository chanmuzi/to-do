import AppKit
@_spi(Verification) import Editor

/// 실제 입력 경로(`insertText`, `doCommand(by:)`, 마우스 누름)를 차례로 흉내 낸다.
///
/// 단계(`;`로 구분):
/// - `type:<글자>`: 한 글자씩 입력. `space`, `tab`, `backtab`, `return`, `backspace`, `delete`
/// - `left`, `right`, `up`, `down`, `home`, `end`
/// - `caret:<줄>`(그 줄 끝), `select:<위치>,<길이>`
/// - `action:<이름>`: `bold`, `strike`, `highlight`, `code`, `codeblock`, `link`, `todo`, `done`,
///   `up`, `down`, `fold`, `unfold`, `h1`, `h2`, `h3`
/// - `click:<줄>`: 그 줄 왼쪽 칸(체크박스, 꺾쇠)을 누름
/// - `hover:<줄>`: 그 줄 글자 위로 마우스를 옮김(코드 블록 복사 버튼, 링크 밑줄)
/// - `cmd:<셀렉터>`: 그 밖의 키 명령(예: `cmd:moveWordLeftAndModifySelection:`)
/// - `link:<주소>`: 떠 있는 링크 주소 칸에 주소를 넣고 확정(`action:link` 뒤에)
/// - `mark:<글자>`(한글 조합 중인 글자), `commit:<글자>`(조합 확정)
/// - `undo`, `redo`
enum DemoScript {
    static func run(_ steps: [String], on editor: MarkdownEditor) -> [String] {
        guard !steps.isEmpty else { return [] }
        var problems: [String] = []
        // 실제로는 키 입력마다 런 루프가 되돌리기 묶음을 닫는다. 여기서는 단계마다 직접 닫는다.
        let undoManager = editor.undoManager
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        for step in steps {
            let isUndo = step == "undo" || step == "redo"
            if !isUndo { undoManager.beginUndoGrouping() }
            if !run(step, on: editor) { problems.append("알 수 없는 단계: \(step)") }
            if !isUndo { undoManager.endUndoGrouping() }
        }
        return problems
    }

    private static func run(_ step: String, on editor: MarkdownEditor) -> Bool {
        let view = editor.textView
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        switch name {
        case "type":
            for character in argument {
                view.insertText(String(character), replacementRange: view.selectedRange())
            }
        case "space": view.insertText(" ", replacementRange: view.selectedRange())
        case "tab": view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        case "backtab": view.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        case "return": view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        case "backspace": view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        case "delete": view.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        case "left": view.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        case "right": view.doCommand(by: #selector(NSResponder.moveRight(_:)))
        case "up": view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        case "down": view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        case "home": view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        case "end": view.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        case "caret":
            guard let line = Int(argument) else { return false }
            placeCaret(atEndOfLine: line, in: editor)
        case "select":
            let numbers = argument.split(separator: ",").compactMap { Int($0) }
            guard numbers.count == 2 else { return false }
            editor.selectedRange = NSRange(location: numbers[0], length: numbers[1])
        case "action":
            guard let action = action(named: argument) else { return false }
            editor.perform(action)
        case "click":
            guard let line = Int(argument), let point = editor.gutterPoint(forLine: line),
                  let window = view.window,
                  let event = NSEvent.mouseEvent(
                      with: .leftMouseDown,
                      location: view.convert(point, to: nil),
                      modifierFlags: [],
                      timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: window.windowNumber,
                      context: nil,
                      eventNumber: 0,
                      clickCount: 1,
                      pressure: 1
                  ) else { return false }
            view.mouseDown(with: event)
        case "hover":
            guard let line = Int(argument), let point = editor.textPoint(forLine: line),
                  let window = view.window,
                  let event = NSEvent.mouseEvent(
                      with: .mouseMoved,
                      location: view.convert(point, to: nil),
                      modifierFlags: [],
                      timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: window.windowNumber,
                      context: nil,
                      eventNumber: 0,
                      clickCount: 0,
                      pressure: 0
                  ) else { return false }
            view.mouseMoved(with: event)
        case "mark":
            view.setMarkedText(argument, selectedRange: NSRange(location: argument.utf16.count, length: 0), replacementRange: view.markedRange().location == NSNotFound ? view.selectedRange() : view.markedRange())
        case "commit":
            view.insertText(argument, replacementRange: view.markedRange().location == NSNotFound ? view.selectedRange() : view.markedRange())
        case "cmd": view.doCommand(by: NSSelectorFromString(argument))
        case "link": editor.commitLink(argument)
        case "undo": editor.undoManager.undo()
        case "redo": editor.undoManager.redo()
        default: return false
        }
        return true
    }

    static func placeCaret(atEndOfLine line: Int, in editor: MarkdownEditor) {
        let lines = editor.text.components(separatedBy: "\n")
        guard line >= 0, line < lines.count else { return }
        let location = lines.prefix(line + 1).reduce(0) { $0 + $1.utf16.count } + line
        editor.selectedRange = NSRange(location: location, length: 0)
    }

    private static func action(named name: String) -> EditorAction? {
        switch name {
        case "bold": .bold
        case "strike": .strikethrough
        case "highlight": .highlight
        case "code": .inlineCode
        case "codeblock": .codeBlock
        case "link": .link
        case "todo": .toggleTodo
        case "done": .toggleDone
        case "up": .moveLineUp
        case "down": .moveLineDown
        case "fold": .fold
        case "unfold": .unfold
        case "h1": .heading(1)
        case "h2": .heading(2)
        case "h3": .heading(3)
        case "indent": .indent
        case "outdent": .outdent
        default: nil
        }
    }
}
