import Foundation
import Models

/// "최근에 연 노트"의 차례(D-033): 마지막으로 연 때가 가까운 노트가 앞이다.
/// 연 때를 적은 적이 없는 노트(이 기록이 생기기 전의 노트, 캡처가 만들고 아직 열지 않은 노트)는 고친 시각으로 대신한다.
nonisolated enum BrowseRecency {
    /// 창 상태에 적힌 "마지막으로 연 때".
    static func openedTimes(from states: [NoteID: NoteWindowState]) -> [NoteID: Date] {
        states.compactMapValues(\.lastOpened)
    }

    /// 때가 같으면 받은 차례(최근에 고친 것이 앞)를 지킨다.
    static func sorted(_ notes: [BrowseIndexedNote], openedTimes: [NoteID: Date]) -> [BrowseIndexedNote] {
        notes.enumerated()
            .map { (offset: $0.offset, note: $0.element, time: openedTimes[$0.element.note.id] ?? $0.element.note.modified) }
            .sorted { $0.time != $1.time ? $0.time > $1.time : $0.offset < $1.offset }
            .map(\.note)
    }
}
