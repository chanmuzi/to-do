import Models
import Routing

/// 지금 고른 줄을 ↑↓로 옮긴다(spec 8). 구획 이름과 구분선은 건너뛰고, 끝에서는 멈춘다.
nonisolated enum BrowseSelection {
    /// 처음에는 맨 윗줄을 고른다.
    static func initial(in entries: [BrowseEntry]) -> Int? {
        entries.firstIndex(where: \.isSelectable)
    }

    /// 목록을 다시 만든 뒤 고를 줄. 노트 줄은 같은 노트(`NoteID`)의 줄이다: 그 노트의 제목, 본문, 리마인더가 바뀌어도
    /// 고른 줄이 따라간다. 그 줄이 없어졌으면 맨 윗줄.
    static func index(keeping selected: BrowseEntry?, in entries: [BrowseEntry]) -> Int? {
        guard let selected else { return initial(in: entries) }
        let kept: Int?
        if case .note(let row) = selected {
            kept = entries.firstIndex {
                if case .note(let other) = $0 { other.id == row.id } else { false }
            }
        } else {
            kept = entries.firstIndex(of: selected)
        }
        return kept ?? initial(in: entries)
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
