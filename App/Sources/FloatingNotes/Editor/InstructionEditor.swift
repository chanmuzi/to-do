import AppKit
import Editor
import Store
import Theme

/// 라이브러리에는 편집기 뷰만 넘긴다. 노트 창의 일정과 파일 명령을 연결하지 않는다.
final class InstructionEditor {
    let editor: MarkdownEditor
    private let store: AgentStore
    private var base = ""

    init(theme: Theme, store: AgentStore) {
        self.store = store
        var config = MarkdownEditorConfiguration()
        config.recognizesDates = false
        editor = MarkdownEditor(theme: theme, configuration: config)
        editor.documentView.setAccessibilityLabel("지침")
        editor.onTextChange = { [weak self] text in
            guard let self else { return }
            store.editInstructions(text, basedOn: base)
        }
        store.collectEditorChange = { [weak editor] in editor?.flushPendingChange() }
        store.instructionsSaved = { [weak self] text in self?.display(text) }
    }

    func open() throws {
        display(try store.instructionSnapshot())
    }

    private func display(_ text: String) {
        base = text
        if !editor.text.utf8.elementsEqual(text.utf8) { editor.applyOutsideChange(to: text) }
    }
}
