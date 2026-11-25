import AppKit
import Editor
import Models
import NotePanel
import Store
import DateTime

/// 본문 편집기의 표시 방식. 설정 화면이 생기면 거기서 바꾼다. 기본값은 `tokens.json`의 `display.defaults`와 같다.
struct NoteEditorOptions: Hashable {
    /// 체크박스 모양(spec 6): 상자(기본) 또는 대괄호.
    var recognizesDates = true
    var checkbox: CheckboxStyle = .box
    /// 인라인 코드의 글자색(spec 6, D-035): 코드 강조색(기본) 또는 무채색.
    var inlineCode: InlineCodeStyle = .accent

    init(checkbox: CheckboxStyle = .box, inlineCode: InlineCodeStyle = .accent) {
        self.checkbox = checkbox
        self.inlineCode = inlineCode
    }

    /// 저장된 설정에서 읽는다. 모르는 이름(더 새 버전이 적은 값, 손으로 고친 파일)은 기본값으로 둔다.
    init(settings: AppSettings) {
        self.init(
            checkbox: CheckboxStyle(rawValue: settings.checkbox) ?? .box,
            inlineCode: InlineCodeStyle(rawValue: settings.inlineCode) ?? .accent
        )
        recognizesDates = settings.recognizesDates
    }

    /// 저장할 설정에 적는다.
    func write(to settings: inout AppSettings) {
        settings.recognizesDates = recognizesDates
        settings.checkbox = checkbox.rawValue
        settings.inlineCode = inlineCode.rawValue
    }
}

/// 노트 창마다 Markdown 편집기를 만들어 넘기는 곳(`NotePanelCoordinator`의 `makeBodyEditor`).
final class NoteEditorFactory {
    /// 바꾸면 떠 있는 편집기에 바로 반영된다.
    var options = NoteEditorOptions() {
        didSet {
            guard options != oldValue else { return }
            for adapter in liveEditors {
                var updated = configuration
                updated.paletteID = adapter.editor.configuration.paletteID
                adapter.editor.configuration = updated
            }
        }
    }

    var onOpenSchedule: ((NoteID, String?, NSView) -> Void)?
    var onDeleteScheduleLines: ((NoteID, String, String, UUID) throws -> InlineDateEffect?)?
    var onAcceptDate: ((NoteID, InlineDateAcceptance) throws -> InlineDateEffect)?
    var onDateError: (Error) -> Void = { _ in }
    private let folds: NoteFoldStore
    private var editors: [NoteID: WeakEditor] = [:]

    init(windowStates: WindowStateStore, log: @escaping (String) -> Void) {
        folds = NoteFoldStore(windowStates: windowStates, log: log)
    }

    /// 표시 방식을 저장된 설정(`app-settings.json`)에 잇는다: 지금 값으로 시작하고, 설정이 바뀔 때마다 따라가
    /// 떠 있는 편집기에 곧바로 반영한다. 바꿀 때는 `settings.update { options.write(to: &$0) }`로 적는다.
    func follow(_ settings: AppSettingsStore) {
        options = NoteEditorOptions(settings: settings.settings)
        settings.onChange = { [weak self] in self?.options = NoteEditorOptions(settings: $0) }
    }

    func makeEditor(_ context: NoteBodyEditorContext) -> any NoteBodyEditing {
        let adapter = MarkdownBodyEditor(
            editor: MarkdownEditor(theme: context.theme, configuration: configuration),
            noteID: context.noteID, folds: folds
        )
        adapter.editor.onOpenSchedule = { [weak self] id, anchor in self?.onOpenSchedule?(context.noteID, id, anchor) }
        adapter.editor.onAcceptDate = { [weak self] request in
            guard let accept = self?.onAcceptDate else { throw CocoaError(.featureUnsupported) }
            return try accept(context.noteID, request)
        }
        adapter.editor.onDeleteScheduleLines = { [weak self] previous, next, token in
            try self?.onDeleteScheduleLines?(context.noteID, previous, next, token)
        }
        adapter.editor.onDateError = { [weak self] error in self?.onDateError(error) }
        editors = editors.filter { $0.value.editor != nil }
        editors[context.noteID] = WeakEditor(editor: adapter)
        return adapter
    }

    /// 그 노트의 창에 들어 있는 편집기. 창이 닫혔으면 `nil`.
    func editor(for id: NoteID) -> MarkdownBodyEditor? {
        editors[id]?.editor
    }

    private var configuration: MarkdownEditorConfiguration {
        var value = MarkdownEditorConfiguration(checkboxStyle: options.checkbox, inlineCodeStyle: options.inlineCode)
        value.recognizesDates = options.recognizesDates
        return value
    }

    private var liveEditors: [MarkdownBodyEditor] {
        editors.values.compactMap(\.editor)
    }

    private struct WeakEditor {
        weak var editor: MarkdownBodyEditor?
    }
}
