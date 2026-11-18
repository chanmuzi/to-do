import AppKit
import Editor
import Models
import NotePanel

/// `MarkdownEditor`(Editor 모듈)를 노트 창의 본문 자리(`NoteBodyEditing`)에 맞춘 어댑터.
/// 두 기능 모듈은 서로를 모르고, App이 이것으로 잇는다.
///
/// - 화면: 노트 창이 스크롤 뷰를 가지므로 편집기의 `documentView`(뒤집힌 좌표, 안쪽 여백 포함)를 넘긴다.
/// - 글: `NoteBodyEditing`의 약속은 편집기가 그대로 지킨다(같은 글이면 아무것도 하지 않음, 다른 글이면
///   되돌리기 기록을 비우고 조합을 끊음, 넣을 때는 알리지 않고 미뤄 둔 알림을 버림, 줄바꿈을 `\n`으로 고쳐 보임).
/// - 접힘: 노트 파일이 아니라 로컬 창 상태에 둔다(D-018, D-023). 줄 번호와 그 줄의 글을 함께 적는다.
///   처음 넣는 글과 함께 되살리는데, 창이 닫힌 사이에 파일이 바뀌었으면 적어 둔 글로 줄을 찾아 옮기거나
///   버린다. 접힘이나 글이 바뀔 때마다 적는다. 떠 있는 동안 밖에서 본문이 바뀌면 줄 번호를 새 본문에 맞춰 옮긴다.
/// - 덧붙이기: 이 편집기가 아닌 쪽이 끝에 붙인 글은 `appendFromOutside`로 받아 커서, 접힘, 되돌리기 기록,
///   조합 중인 글자를 그대로 둔다.
final class MarkdownBodyEditor: NoteBodyEditing, NoteBodyFormatting {
    var isEditingBody: Bool { editor.isEditingBody }
    var activeFormats: Set<NoteFormat> {
        let state = editor.formattingState
        return Set(NoteFormat.allCases.filter {
            switch $0 {
            case .bold: state.bold
            case .strike: state.strikethrough
            case .highlight: state.highlight > 0
            case .code: state.inlineCode
            case .link: state.link
            case .checklist: state.checklist
            case .bullet: state.bullet
            }
        })
    }

    var onFormattingChange: (() -> Void)? {
        get { editor.onFormattingChange }
        set { editor.onFormattingChange = newValue }
    }

    func setNotePalette(_ id: String?) {
        if editor.configuration.paletteID != id { editor.configuration.paletteID = id }
    }

    func applyFormat(_ format: NoteFormat) {
        editor.focus()
        let action: EditorAction = switch format {
        case .bold: .bold
        case .strike: .strikethrough
        case .highlight: .highlight
        case .code: .inlineCode
        case .link: .link
        case .checklist: .toggleTodo
        case .bullet: .toggleBullet
        }
        editor.perform(action)
    }

    let editor: MarkdownEditor
    var onTextChange: ((String) -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?

    private let noteID: NoteID
    private let folds: NoteFoldStore
    private var hasLoaded = false

    init(editor: MarkdownEditor, noteID: NoteID, folds: NoteFoldStore) {
        self.editor = editor
        self.noteID = noteID
        self.folds = folds
        editor.onTextChange = { [unowned self] in
            // 접힌 줄의 글이 바뀌었을 수 있다(토글 줄을 고침). 적어 둔 글이 낡으면 다시 열 때 접힘을 잃는다.
            saveFolds()
            onTextChange?($0)
        }
        editor.onContentHeightChange = { [unowned self] in onContentHeightChange?($0) }
        editor.onFoldChange = { [unowned self] _ in saveFolds() }
    }

    var view: NSView { editor.documentView }

    var text: String {
        get { editor.text }
        set {
            guard hasLoaded else {
                // 노트를 연다: 원문과 지난번의 접힘을 한 번에 넣는다. 접힘은 지금 본문에 맞춰 되살린 것이다.
                hasLoaded = true
                editor.load(text: newValue, foldedLines: folds.foldedLines(for: noteID, in: newValue))
                saveFolds()
                return
            }
            // 이 편집기가 아닌 쪽이 본문을 바꿨다. 같은 글이면 편집기가 아무것도 하지 않는다.
            let folded = FoldPersistence.remapped(editor.foldedLines, from: editor.text, to: newValue)
            editor.load(text: newValue, foldedLines: folded)
            saveFolds()
        }
    }

    func appendFromOutside(_ suffix: String) {
        editor.appendFromOutside(suffix)
        saveFolds()
    }

    /// 이 앱의 다른 곳이 본문을 바꿨다(끝에 붙인 것이 아닌 변경 포함). 달라진 부분만 바꿔 넣어
    /// 되돌리기 기록, 접힘, 커서, 조합 중인 글자를 지킨다.
    func applyOutsideChange(to newText: String) {
        guard hasLoaded else {
            text = newText
            return
        }
        editor.applyOutsideChange(to: newText)
        saveFolds()
    }

    func setTitleFocusAction(_ action: @escaping () -> Void) {
        editor.onFocusTitle = action
    }

    func scheduleRemoved(fromBodyLine line: Int) {
        editor.scheduleRemoved(fromBodyLine: line)
    }

    func focus() {
        editor.focus()
    }

    func flushPendingChange() {
        editor.flushPendingChange()
    }

    /// 지금 접힘과 그 줄들의 글을 적는다. 적어 둔 것과 같으면 저장소가 파일을 쓰지 않는다.
    /// (`load`는 접힘을 알리지 않으므로, 새 본문에서 걸러진 결과도 여기서 적는다.)
    private func saveFolds() {
        let folded = editor.foldedLines
        // 접힌 것이 없고 적어 둔 것도 없으면 본문을 줄로 나눌 필요가 없다(글자를 칠 때마다 불린다).
        guard !folded.isEmpty || folds.hasStoredFolds(for: noteID) else { return }
        folds.save(folded, in: editor.text, for: noteID)
    }
}
