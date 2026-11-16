import Foundation
import Models
import Store

/// 캡처한 한 줄을 저장소에 넣는다. 항목 단위로만 고친다(D-016).
struct CaptureWriter {
    enum Outcome: Hashable {
        /// 오늘 노트에 붙였다.
        case appended(NoteID)
        /// 오늘 노트가 없어 새로 만들었다.
        case created(NoteID)
        /// 오늘 노트가 이미 충돌 상태다. 붙인 줄은 저장소에 남아 있고, 충돌을 풀 때 함께 쓰인다.
        case heldByConflict(NoteID)

        var noteID: NoteID {
            switch self {
            case .appended(let id), .created(let id), .heldByConflict(let id): id
            }
        }
    }

    let notes: any NoteStoring
    var calendar: Calendar = .current

    /// - Throws: 목록을 읽지 못했거나 쓰지 못했을 때의 `StoreError`. 이때는 아무것도 넣지 않은 것이다.
    func add(_ entry: CaptureInterpretation, now: Date) throws -> Outcome {
        let existing = try notes.list().notes
        guard let note = CaptureDestination.todayNote(
            in: existing, spaceID: entry.spaceID, now: now, calendar: calendar
        ) else {
            let created = try notes.create(NoteDraft(
                title: CaptureDestination.title(for: now, calendar: calendar),
                body: TodoAppender.append(entry.text, to: ""),
                spaceID: entry.spaceID,
                reminder: entry.reminder
            ))
            return .created(created.id)
        }

        // 쓰지 않은 변경이 없으면 디스크의 지금 글을 기준으로 삼는다(다른 프로그램이 고친 뒤일 수 있다).
        // 편집기가 미뤄 둔 글이 있으면 `update`의 클로저가 그 글을 받으므로 그 뒤에 붙는다.
        if !notes.hasPendingChanges(note.id) { _ = try notes.load(note.id) }
        do {
            try notes.update(note.id) { current in
                current.body = TodoAppender.append(entry.text, to: current.body)
                current.reminder = ReminderRule.merged(existing: current.reminder, new: entry.reminder)
            }
            return .appended(note.id)
        } catch StoreError.conflict {
            return .heldByConflict(note.id)
        }
    }
}
