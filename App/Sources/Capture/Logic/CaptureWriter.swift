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
        /// 오늘 노트(`from`)에 풀리지 않은 문제(충돌, 없어진 파일)가 있어 다른 노트(`to`)에 넣었다.
        /// `to`는 오늘의 다음 노트이거나, 없으면 새로 만든 노트다.
        case redirected(to: NoteID, from: NoteID, reason: StoreError)

        /// 줄이 실제로 들어간 노트.
        var noteID: NoteID {
            switch self {
            case .appended(let id), .created(let id), .redirected(let id, _, _): id
            }
        }
    }

    let notes: any NoteStoring
    var calendar: Calendar = .current
    var onScheduleCreated: (@MainActor (NoteID, String) -> Void)?

    /// 줄은 언제나 디스크에 쓰인 노트에 들어간다. 저장소의 "쓰지 못한 변경"에만 남겨 두고 성공으로 치지 않는다.
    /// - Throws: 목록을 읽지 못했거나 쓰지 못했을 때의 `StoreError`. 이때는 아무것도 넣지 않은 것이다.
    func add(_ entry: CaptureInterpretation, now: Date) throws -> Outcome {
        let candidates = CaptureDestination.todayNotes(
            in: try notes.list().notes.filter { !$0.isArchived }, spaceID: entry.spaceID, now: now, calendar: calendar
        )
        var blocked: (id: NoteID, reason: StoreError)?
        for note in candidates {
            do {
                try append(entry, to: note.id, now: now)
                return blocked.map { .redirected(to: note.id, from: $0.id, reason: $0.reason) } ?? .appended(note.id)
            } catch let error as StoreError where Self.isUnresolvedProblem(error) {
                blocked = blocked ?? (note.id, error)
            }
        }
        let created = try notes.create(NoteDraft(
            title: CaptureDestination.title(for: now, calendar: calendar),
            body: TodoAppender.append(entry.text, to: ""),
            spaceID: entry.spaceID,
            schedules: entry.schedule(now: now, line: 0, calendar: calendar).map { [$0] }
        ))
        created.schedules.forEach { onScheduleCreated?(created.id, $0.id) }
        return blocked.map { .redirected(to: created.id, from: $0.id, reason: $0.reason) } ?? .created(created.id)
    }

    /// 그 노트에 줄을 붙여 곧바로 쓴다.
    /// - Throws: 노트가 충돌 중이면 `conflict`, 파일이 없어졌으면 `noteNotFound`. 이때 줄은 저장소에 올리지 않는다.
    private func append(_ entry: CaptureInterpretation, to id: NoteID, now: Date) throws {
        if notes.hasPendingChanges(id) {
            // 편집기가 미뤄 둔 변경을 먼저 쓴다. 충돌 중이거나 파일이 없어진 노트는 여기서 드러난다.
            // 줄을 올리기 전에 알아야 그 줄이 쓰이지 못한 변경에만 남지 않는다.
            try notes.update(id) { _ in }
        } else {
            // 쓰지 않은 변경이 없으면 디스크의 지금 글을 기준으로 삼는다(다른 프로그램이 고친 뒤일 수 있다).
            _ = try notes.load(id)
        }
        var createdID: String?
        try notes.update(id) { current in
            current.body = TodoAppender.append(entry.text, to: current.body)
            if let item = entry.schedule(now: now, line: max(0, current.body.components(separatedBy: "\n").count - 2), calendar: calendar) {
                current.schedules.append(item)
                createdID = item.id
            }
        }
        if let createdID { onScheduleCreated?(id, createdID) }
    }

    /// 사용자가 풀어야 하는 문제인지. 이런 노트는 건너뛰고 다른 노트에 넣는다.
    private static func isUnresolvedProblem(_ error: StoreError) -> Bool {
        switch error {
        case .conflict, .noteNotFound: true
        default: false
        }
    }
}
