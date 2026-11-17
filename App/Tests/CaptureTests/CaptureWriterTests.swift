import Foundation
import Models
import Store
import Testing
@testable import Capture

/// 캡처한 줄을 실제 저장소(임시 폴더)에 넣는다. 노트의 만든 날짜는 저장소가 실제 시각으로 적으므로,
/// "지금"은 방금 만든 노트의 만든 시각으로 준다(자정을 넘기는 순간에 돌려도 같은 날이다).
@MainActor
@Suite struct CaptureWriterTests {
    private let fixture: CaptureFixture
    private let writer: CaptureWriter
    private let work = CaptureFixture.work.id
    private let home = CaptureFixture.home.id

    init() throws {
        fixture = try CaptureFixture()
        writer = CaptureWriter(notes: fixture.notes)
    }

    private func entry(_ raw: String, space: SpaceID?, reminder: Date? = nil, now: Date = Date()) -> CaptureInterpretation {
        CaptureInterpretation(
            raw: raw, spaces: fixture.spaces.spaces, selectedSpace: space, manualReminder: reminder,
            now: now, calendar: .current
        )
    }

    /// 초 아래를 버린 시각(파일에는 초 단위로 적힌다).
    private func seconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    @Test func appendsATodoToTodaysNoteOnDisk() throws {
        defer { fixture.cleanUp() }
        let today = try fixture.notes.create(NoteDraft(title: "오늘 할 일", body: "[ ] PR 리뷰\n", spaceID: work))
        let other = try fixture.notes.create(NoteDraft(title: "개인", body: "장보기\n", spaceID: home))

        let outcome = try writer.add(entry("배포 체크리스트 확인", space: work), now: today.created)

        #expect(outcome == .appended(today.id))
        #expect(try fixture.fileText(today.id).hasSuffix("---\n[ ] PR 리뷰\n[ ] 배포 체크리스트 확인\n"))
        #expect(try fixture.fileText(other.id).hasSuffix("---\n장보기\n"))
        #expect(!fixture.notes.hasPendingChanges(today.id))
        #expect(try fixture.notes.list().notes.count == 2)
    }

    @Test func createsTodaysNoteWhenTheSpaceHasNone() throws {
        defer { fixture.cleanUp() }
        let now = try fixture.notes.create(NoteDraft(title: "회사 노트", body: "", spaceID: work)).created
        let reminder = seconds(now.addingTimeInterval(3600))

        let outcome = try writer.add(entry("치과 예약", space: home, reminder: reminder), now: now)

        guard case .created(let id) = outcome else {
            Issue.record("새 노트를 만들어야 한다: \(outcome)")
            return
        }
        let created = try fixture.notes.load(id)
        #expect(created.spaceID == home)
        #expect(created.body == "[ ] 치과 예약\n")
        #expect(created.reminder == reminder)
        #expect(created.title == CaptureDestination.title(for: now, calendar: .current))
        #expect(try fixture.fileText(id).hasSuffix("---\n[ ] 치과 예약\n"))
        // 한 번 더 넣으면 방금 만든 노트에 붙는다.
        #expect(try writer.add(entry("택배 반품", space: home), now: created.created) == .appended(id))
        #expect(try fixture.notes.load(id).body == "[ ] 치과 예약\n[ ] 택배 반품\n")
    }

    /// 어제 만든 노트는 오늘 노트가 아니다(노트는 만든 날짜에 속한다).
    @Test func notesFromOtherDaysAreNotUsed() throws {
        defer { fixture.cleanUp() }
        let existing = try fixture.notes.create(NoteDraft(title: "회사", body: "메모\n", spaceID: work))
        let tomorrow = existing.created.addingTimeInterval(86400)

        let outcome = try writer.add(entry("내일 일", space: work, now: tomorrow), now: tomorrow)

        guard case .created(let id) = outcome else {
            Issue.record("새 노트를 만들어야 한다: \(outcome)")
            return
        }
        #expect(id != existing.id)
        #expect(try fixture.notes.load(existing.id).body == "메모\n")
    }

    /// 편집기가 미뤄 둔 글(아직 쓰지 않은 본문)이 있으면 그 글 뒤에 붙는다. 서로의 변경을 지우지 않는다(D-016).
    @Test func mergesWithAPendingEditorUpdate() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음 글\n", spaceID: work))
        try fixture.notes.scheduleUpdate(note.id) { $0.body = "처음 글\n편집기에서 쓰는 중" }
        try fixture.notes.scheduleUpdate(note.id) { $0.title = "고친 제목" }
        #expect(fixture.notes.hasPendingChanges(note.id))
        #expect(try fixture.fileText(note.id).hasSuffix("---\n처음 글\n"))

        let outcome = try writer.add(entry("캡처한 일", space: work), now: note.created)

        #expect(outcome == .appended(note.id))
        let saved = try fixture.fileText(note.id)
        #expect(saved.hasSuffix("---\n처음 글\n편집기에서 쓰는 중\n[ ] 캡처한 일\n"))
        #expect(saved.contains("title: \"고친 제목\""))
        #expect(!fixture.notes.hasPendingChanges(note.id))
        // 편집기가 그 뒤에 제 글을 다시 넘겨도(항목 단위) 제목 같은 다른 항목은 남는다.
        try fixture.notes.scheduleUpdate(note.id) { $0.body += "\n" }
        #expect(try fixture.notes.load(note.id).title == "고친 제목")
    }

    @Test func reminderGoesToTheNoteAndTheEarliestWins() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        let base = seconds(note.created)
        let now = note.created

        _ = try writer.add(entry("늦은 일", space: work, reminder: base.addingTimeInterval(7200)), now: now)
        #expect(try fixture.notes.load(note.id).reminder == base.addingTimeInterval(7200))

        _ = try writer.add(entry("이른 일", space: work, reminder: base.addingTimeInterval(1800)), now: now)
        #expect(try fixture.notes.load(note.id).reminder == base.addingTimeInterval(1800))

        _ = try writer.add(entry("더 늦은 일", space: work, reminder: base.addingTimeInterval(86400)), now: now)
        _ = try writer.add(entry("리마인더 없는 일", space: work), now: now)
        let saved = try fixture.notes.load(note.id)
        #expect(saved.reminder == base.addingTimeInterval(1800))
        #expect(saved.body == "[ ] 늦은 일\n[ ] 이른 일\n[ ] 더 늦은 일\n[ ] 리마인더 없는 일\n")
    }

    /// 다른 프로그램이 파일을 고친 뒤에도(쓰지 않은 변경이 없을 때) 그 글 뒤에 붙는다. 충돌이 아니다.
    @Test func appendsAfterAnExternalEdit() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음\n", spaceID: work))
        let url = fixture.location.notesDirectory.appendingPathComponent("\(note.id.rawValue).md")
        let edited = try fixture.fileText(note.id).replacingOccurrences(of: "처음\n", with: "처음\n밖에서 더한 줄\n")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        let outcome = try writer.add(entry("캡처한 일", space: work), now: note.created)

        #expect(outcome == .appended(note.id))
        #expect(try fixture.fileText(note.id).hasSuffix("---\n처음\n밖에서 더한 줄\n[ ] 캡처한 일\n"))
    }

    /// 편집기의 쓰지 않은 글이 있는데 다른 프로그램이 파일을 고쳤다(충돌): 그 노트에는 넣지 않는다.
    /// 줄을 쓰지 못한 변경에만 얹어 두면 넣은 것처럼 보이고 디스크에는 없다. 새 노트를 만들어 거기에 쓴다.
    @Test func conflictedNoteIsSkippedAndTheLineGoesToANewNote() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음\n", spaceID: work))
        try fixture.notes.scheduleUpdate(note.id) { $0.body = "처음\n편집 중\n" }
        let url = fixture.location.notesDirectory.appendingPathComponent("\(note.id.rawValue).md")
        let external = try fixture.fileText(note.id).replacingOccurrences(of: "처음\n", with: "밖에서 바꿈\n")
        try external.write(to: url, atomically: true, encoding: .utf8)
        let reminder = seconds(note.created.addingTimeInterval(3600))

        let outcome = try writer.add(entry("캡처한 일", space: work, reminder: reminder), now: note.created)

        guard case .redirected(let createdID, from: note.id, reason: .conflict(note.id)) = outcome else {
            Issue.record("충돌 중인 노트를 건너뛰고 새 노트에 넣어야 한다: \(outcome)")
            return
        }
        #expect(createdID != note.id)
        let created = try fixture.notes.load(createdID)
        #expect(created.title == CaptureDestination.title(for: note.created, calendar: .current))
        #expect(created.spaceID == work)
        #expect(created.reminder == reminder)
        #expect(try fixture.fileText(createdID).hasSuffix("---\n[ ] 캡처한 일\n"))
        #expect(!fixture.notes.hasPendingChanges(createdID))
        // 충돌 중인 노트: 디스크도, 쓰지 못한 변경도 건드리지 않았다. 풀 때 줄이 겹쳐 들어가지 않는다.
        #expect(try fixture.fileText(note.id) == external)
        #expect(try fixture.notes.load(note.id).body == "처음\n편집 중\n")
        #expect(try fixture.notes.load(note.id).reminder == nil)

        // 그다음에 넣는 줄은 방금 만든 노트로 간다(넣을 때마다 새 노트를 만들지 않는다).
        // 두 노트를 같은 초에 만들었으면 차례가 id로 정해지므로, 어느 쪽을 먼저 봤는지는 견주지 않는다.
        let second = try writer.add(entry("또 캡처한 일", space: work), now: created.created)
        #expect(second.noteID == createdID)
        #expect(try fixture.fileText(createdID).hasSuffix("---\n[ ] 캡처한 일\n[ ] 또 캡처한 일\n"))
        #expect(try fixture.notes.list().notes.count == 2)
        #expect(try fixture.notes.load(note.id).body == "처음\n편집 중\n")

        // 충돌을 풀고 나면 그 노트에도 다시 넣을 수 있다. 새 노트는 더 만들지 않는다.
        _ = try fixture.notes.resolveConflict(note.id, keeping: .mine)
        let third = try writer.add(entry("푼 뒤의 일", space: work), now: created.created)
        #expect(third == .appended(third.noteID))
        #expect(try fixture.fileText(third.noteID).hasSuffix("[ ] 푼 뒤의 일\n"))
        #expect(try fixture.notes.list().notes.count == 2)
    }

    /// 오늘 노트가 둘이고 먼저 만든 것이 충돌 중이면 다음 노트에 넣는다.
    @Test func laterTodayNoteIsUsedWhenTheFirstIsBlocked() {
        let first = Note(id: NoteID(rawValue: "a"), spaceID: work, created: TestClock.date(11, 16, 8), modified: TestClock.now)
        let second = Note(id: NoteID(rawValue: "b"), spaceID: work, created: TestClock.date(11, 16, 9), modified: TestClock.now)
        let ordered = CaptureDestination.todayNotes(
            in: [second, first], spaceID: work, now: TestClock.now, calendar: TestClock.calendar
        )
        #expect(ordered.map(\.id.rawValue) == ["a", "b"])
    }

    /// 목록에는 있는데 파일이 없어진 노트(읽는 사이에 지워짐): 건너뛰고 새 노트에 넣는다.
    @Test func noteWithAMissingFileIsSkippedAndTheLineGoesToANewNote() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음\n", spaceID: work))
        let store = FaultyNoteStore(base: fixture.notes)
        store.faults = [note.id: .noteNotFound(note.id)]

        let outcome = try CaptureWriter(notes: store).add(entry("캡처한 일", space: work), now: note.created)

        guard case .redirected(let createdID, from: note.id, reason: .noteNotFound(note.id)) = outcome else {
            Issue.record("없어진 노트를 건너뛰고 새 노트에 넣어야 한다: \(outcome)")
            return
        }
        #expect(try fixture.fileText(createdID).hasSuffix("---\n[ ] 캡처한 일\n"))
        #expect(try fixture.fileText(note.id).hasSuffix("---\n처음\n"))
        #expect(!fixture.notes.hasPendingChanges(note.id))
    }

    /// 쓰지 못한 다른 까닭(권한 등)은 건너뛰지 않고 그대로 알린다. 아무것도 넣지 않은 것이다.
    @Test func otherWriteFailuresAreThrown() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "처음\n", spaceID: work))
        let store = FaultyNoteStore(base: fixture.notes)
        store.faults = [note.id: .writeFailed(note.id, message: "쓸 수 없음")]
        #expect(throws: StoreError.writeFailed(note.id, message: "쓸 수 없음")) {
            _ = try CaptureWriter(notes: store).add(entry("캡처한 일", space: work), now: note.created)
        }
        #expect(try fixture.notes.list().notes.count == 1)
        #expect(try fixture.fileText(note.id).hasSuffix("---\n처음\n"))
    }

    /// 이미 지난 리마인더가 걸려 있던 노트: 지난 값이 새 리마인더를 막지 않는다.
    @Test func pastExistingReminderDoesNotBlockANewOne() throws {
        defer { fixture.cleanUp() }
        let note = try fixture.notes.create(NoteDraft(title: "오늘", body: "", spaceID: work))
        let base = seconds(note.created)
        try fixture.notes.update(note.id) { $0.reminder = base.addingTimeInterval(-3600) }

        _ = try writer.add(entry("새 일", space: work, reminder: base.addingTimeInterval(7200)), now: note.created)
        let saved = try fixture.notes.load(note.id)
        #expect(saved.schedules.count == 2)
        #expect(saved.displayedSchedule(at: note.created)?.start == base.addingTimeInterval(7200))
    }

    @Test func noSpaceUsesTodaysNoteWithoutASpace() throws {
        defer { fixture.cleanUp() }
        _ = try fixture.notes.create(NoteDraft(title: "회사", body: "", spaceID: work))
        let loose = try fixture.notes.create(NoteDraft(title: "스크래치", body: "", spaceID: nil))

        #expect(try writer.add(entry("아무 데나", space: nil), now: loose.created) == .appended(loose.id))
        #expect(try fixture.notes.load(loose.id).body == "[ ] 아무 데나\n")
    }
}


extension CaptureWriterTests {
    @Test func registrationCallbackOnlyContainsNewlyCapturedSchedules() throws {
        defer { fixture.cleanUp() }
        var requests: [(NoteID, String)] = []
        let writer = CaptureWriter(notes: fixture.notes, onScheduleCreated: { requests.append(($0, $1)) })
        let now = Date()
        let first = try writer.add(entry("새 알림", space: work, reminder: now.addingTimeInterval(3600)), now: now)
        #expect(requests.count == 1)
        #expect(requests[0].0 == first.noteID)
        #expect(try fixture.notes.load(first.noteID).schedules[0].id == requests[0].1)
        let legacy = try fixture.notes.create(NoteDraft(body: "옛 글", spaceID: home, reminder: now.addingTimeInterval(3600)))
        let appended = try writer.add(entry("다음 알림", space: home, reminder: now.addingTimeInterval(7200)), now: legacy.created)
        #expect(appended.noteID == legacy.id)
        #expect(requests.count == 2)
        #expect(requests[1].0 == legacy.id)
        #expect(!requests[1].1.hasPrefix("legacy-"))
        #expect(try fixture.notes.load(legacy.id).schedules[1].id == requests[1].1)
        _ = try writer.add(entry("본문만", space: home), now: legacy.created)
        #expect(requests.count == 2)
    }
}
