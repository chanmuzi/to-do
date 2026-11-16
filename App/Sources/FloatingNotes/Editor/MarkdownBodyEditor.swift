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
/// - 접힘: 노트 파일이 아니라 로컬 창 상태에 둔다(D-018, D-023). 처음 넣는 글과 함께 되살리고,
///   바뀔 때마다 적는다. 밖에서 본문이 바뀌면 줄 번호를 새 본문에 맞춰 옮긴다.
final class MarkdownBodyEditor: NoteBodyEditing {
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
        editor.onTextChange = { [unowned self] in onTextChange?($0) }
        editor.onContentHeightChange = { [unowned self] in onContentHeightChange?($0) }
        editor.onFoldChange = { [unowned self] in self.folds.save($0, for: self.noteID) }
    }

    var view: NSView { editor.documentView }

    var text: String {
        get { editor.text }
        set {
            guard hasLoaded else {
                // 노트를 연다: 원문과 지난번의 접힘을 한 번에 넣는다.
                hasLoaded = true
                editor.load(text: newValue, foldedLines: folds.foldedLines(for: noteID))
                saveFoldsIfChanged()
                return
            }
            // 이 편집기가 아닌 쪽이 본문을 바꿨다. 같은 글이면 편집기가 아무것도 하지 않는다.
            let folded = FoldPersistence.remapped(editor.foldedLines, from: editor.text, to: newValue)
            editor.load(text: newValue, foldedLines: folded)
            saveFoldsIfChanged()
        }
    }

    func focus() {
        editor.focus()
    }

    func flushPendingChange() {
        editor.flushPendingChange()
    }

    /// `load`는 접힘을 알리지 않는다. 새 본문에서 걸러진 결과가 적어 둔 것과 다르면 적는다.
    private func saveFoldsIfChanged() {
        guard editor.foldedLines != folds.foldedLines(for: noteID) else { return }
        folds.save(editor.foldedLines, for: noteID)
    }
}
