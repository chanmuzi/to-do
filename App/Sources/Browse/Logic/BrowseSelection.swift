import Models
import Routing

/// 지금 고른 줄을 ↑↓로 옮긴다(spec 8). 구획 이름과 구분선은 건너뛰고, 끝에서는 멈춘다.
nonisolated enum BrowseSelection {
    /// 처음에는 맨 윗줄을 고른다.
    static func initial(in entries: [BrowseEntry]) -> Int? {
        entries.firstIndex(where: \.isSelectable)
    }

    static func moved(from current: Int?, by step: Int, in entries: [BrowseEntry]) -> Int? {
        let selectable = entries.indices.filter { entries[$0].isSelectable }
        guard !selectable.isEmpty else { return nil }
        guard let current, let position = selectable.firstIndex(of: current) else {
            return step < 0 ? selectable.last : selectable.first
        }
        return selectable[min(max(position + step, 0), selectable.count - 1)]
    }

    /// 그 줄을 열 때 보낼 요청. 고를 수 없는 줄이면 `nil`.
    /// - Parameter current: 노트 찾기를 연 노트. 새 노트는 그 옆에 뜬다.
    static func route(for entry: BrowseEntry, current: NoteID?) -> Route? {
        switch entry {
        case .note(let row): .openNote(row.id)
        case .create(let query): .newNote(NewNoteRequest(draft: NoteDraft(title: query), nextTo: current))
        case .library: .openLibrary
        case .header, .separator: nil
        }
    }
}
