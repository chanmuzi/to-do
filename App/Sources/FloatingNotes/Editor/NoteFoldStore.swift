import Models
import Store

/// 노트마다 접힌 줄을 `WindowStateStore`(`stateDirectory/windows.json`)의 창 상태에 넣어 둔다.
/// 창 상태와 함께 살고 함께 지워진다(노트를 휴지통으로 보내면 없어지고, 되돌리면 돌아온다).
struct NoteFoldStore {
    let windowStates: WindowStateStore
    /// 상태 파일을 쓰지 못했을 때. 편집은 계속할 수 있으므로 기록만 남긴다.
    let log: (String) -> Void

    func foldedLines(for id: NoteID) -> Set<Int> {
        FoldPersistence.lines(from: windowStates.state(for: id)?.foldedLines)
    }

    func save(_ lines: Set<Int>, for id: NoteID) {
        var state = windowStates.state(for: id) ?? NoteWindowState()
        state.foldedLines = FoldPersistence.stored(lines)
        do {
            try windowStates.set(state, for: id)
        } catch {
            log("접힌 줄을 저장하지 못했습니다(\(id)): \(error)")
        }
    }
}
