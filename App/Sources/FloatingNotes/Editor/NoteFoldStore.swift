import Models
import Store

/// 노트마다 접힌 줄을 `WindowStateStore`(`stateDirectory/windows.json`)의 창 상태에 넣어 둔다.
/// 창 상태와 함께 살고 함께 지워진다(노트를 휴지통으로 보내면 없어지고, 되돌리면 돌아온다).
/// 줄 번호 옆에 그 줄의 글도 적어, 창이 닫힌 사이에 파일이 바뀌었으면 다시 열 때 맞춰 옮기거나 버린다.
struct NoteFoldStore {
    let windowStates: WindowStateStore
    /// 상태 파일을 쓰지 못했을 때. 편집은 계속할 수 있으므로 기록만 남긴다.
    let log: (String) -> Void

    /// 저장해 둔 접힘을 지금 본문 `text`에 맞춰 되살린 줄 번호.
    func foldedLines(for id: NoteID, in text: String) -> Set<Int> {
        let state = windowStates.state(for: id)
        return FoldPersistence.restored(lines: state?.foldedLines, texts: state?.foldedLineTexts, in: text)
    }

    func openedEmptyToggleLines(for id: NoteID, in text: String) -> Set<Int> {
        let state = windowStates.state(for: id)
        return FoldPersistence.restored(lines: state?.openedEmptyToggleLines, texts: state?.openedEmptyToggleLineTexts, in: text)
    }

    func hasStoredFolds(for id: NoteID) -> Bool {
        let state = windowStates.state(for: id)
        return state?.foldedLines != nil || state?.openedEmptyToggleLines != nil
    }

    /// 접힌 줄 번호와 그 줄의 글(`text`에서 읽는다)을 적는다. 적힌 것과 같으면 파일을 쓰지 않는다.
    func save(_ lines: Set<Int>, openedEmpty: Set<Int> = [], in text: String, for id: NoteID) {
        var state = windowStates.state(for: id) ?? NoteWindowState()
        let stored = FoldPersistence.stored(lines, in: text)
        state.foldedLines = stored?.lines
        state.foldedLineTexts = stored?.texts
        let opened = FoldPersistence.stored(openedEmpty, in: text)
        state.openedEmptyToggleLines = opened?.lines
        state.openedEmptyToggleLineTexts = opened?.texts
        do {
            try windowStates.set(state, for: id)
        } catch {
            log("접힌 줄을 저장하지 못했습니다(\(id)): \(error)")
        }
    }
}
