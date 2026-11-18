import Foundation
import Models

/// 포커스를 받은 시각이 같은 노트는 저장소의 순서를 유지한다.
nonisolated enum BrowseRecency {
    /// 창 상태에 적힌 "마지막으로 연 때".
    static func openedTimes(from states: [NoteID: NoteWindowState]) -> [NoteID: Date] {
        states.compactMapValues(\.lastOpened)
    }

    /// 때가 같으면 받은 차례(최근에 고친 것이 앞)를 지킨다.
    static func sorted(_ notes: [BrowseIndexedNote], openedTimes: [NoteID: Date]) -> [BrowseIndexedNote] {
        notes.sorted { lhs, rhs in
            let left = openedTimes[lhs.note.id] ?? Date.distantPast
            let right = openedTimes[rhs.note.id] ?? Date.distantPast
            return left > right
        }
    }
}
