import Editor
import Models
import NotePanel
import Store

/// 본문 편집기의 표시 방식. 설정 화면이 생기면 거기서 바꾼다. 기본값은 `tokens.json`의 `display.defaults`와 같다.
struct NoteEditorOptions: Hashable {
    /// 체크박스 모양(spec 6): 상자(기본) 또는 대괄호.
    var checkbox: CheckboxStyle = .box
    /// 인라인 코드의 글자색(spec 6, D-035): 코드 강조색(기본) 또는 무채색.
    var inlineCode: InlineCodeStyle = .accent
}

/// 노트 창마다 Markdown 편집기를 만들어 넘기는 곳(`NotePanelCoordinator`의 `makeBodyEditor`).
final class NoteEditorFactory {
    /// 바꾸면 떠 있는 편집기에 바로 반영된다.
    var options = NoteEditorOptions() {
        didSet {
            guard options != oldValue else { return }
            liveEditors.forEach { $0.editor.configuration = configuration }
        }
    }

    private let folds: NoteFoldStore
    private var editors: [NoteID: WeakEditor] = [:]

    init(windowStates: WindowStateStore, log: @escaping (String) -> Void) {
        folds = NoteFoldStore(windowStates: windowStates, log: log)
    }

    func makeEditor(_ context: NoteBodyEditorContext) -> any NoteBodyEditing {
        let adapter = MarkdownBodyEditor(
            editor: MarkdownEditor(theme: context.theme, configuration: configuration),
            noteID: context.noteID, folds: folds
        )
        editors = editors.filter { $0.value.editor != nil }
        editors[context.noteID] = WeakEditor(editor: adapter)
        return adapter
    }

    /// 그 노트의 창에 들어 있는 편집기. 창이 닫혔으면 `nil`.
    func editor(for id: NoteID) -> MarkdownBodyEditor? {
        editors[id]?.editor
    }

    private var configuration: MarkdownEditorConfiguration {
        MarkdownEditorConfiguration(checkboxStyle: options.checkbox, inlineCodeStyle: options.inlineCode)
    }

    private var liveEditors: [MarkdownBodyEditor] {
        editors.values.compactMap(\.editor)
    }

    private struct WeakEditor {
        weak var editor: MarkdownBodyEditor?
    }
}
