import Foundation
import Testing
import Models
import Store
import Scheduling
@testable import Reminders

@Suite @MainActor struct ScheduleServiceTests {
    private func fixture() throws -> Fixture { try Fixture() }

    @Test func idleStartupDoesNotConstructBridgeOrRequestPermissions() async throws {
        let f = try fixture(); defer { f.close() }
        await f.service.flush()
        #expect(f.constructed == 0)
        #expect(f.bridge.authorizationRequests.isEmpty)
        #expect(f.notifier.permissionRequests == 0)
    }
    @Test func calendarRangeRequiresExistingAccessAndRefreshesUnlinkedEvents() throws {
        let f = try fixture(); defer { f.close() }
        let start = Date()
        let interval = DateInterval(start: start, duration: 86400)
        let fake = FakeCalendarBridge(sampleEventsAt: start)
        let service = ScheduleService(notes: f.notes, notifier: f.notifier, makeBridge: { fake })
        defer { service.stop() }
        fake.isAllowed = false
        #expect(service.events(in: interval).isEmpty && fake.eventRangeReads == 0)
        fake.isAllowed = true
        fake.items["미리 알림"] = ScheduleItem(start: start)
        let events = service.events(in: interval)
        #expect(events.count == 2 && events.allSatisfy { $0.item.kind == .event })
        let event = try #require(events.first)
        #expect(event.calendarURL?.host == "ekevent")
        #expect(event.calendarURL?.lastPathComponent == event.item.link?.localID)
        var visible = events
        service.calendarChanged = { visible = service.events(in: interval) }
        fake.deleteExternally(event.item.id)
        #expect(visible.count == 1 && visible.first != event)
        #expect(fake.authorizationPromptAttempts.isEmpty && f.notifier.permissionRequests == 0)
    }

    @Test func createChangeCompleteDeleteBothDirectionsPreservesText() async throws {
        let f = try fixture(); defer { f.close() }
        let item = ScheduleItem(start: future, title: "원문", todo: TodoAnchor(line: 0, text: "원문"))
        let note = try f.create(NoteDraft(title: "노트 제목", body: "[ ] 원문\n다른 글", schedules: [item]))
        await f.service.flush()
        #expect(f.bridge.authorizationRequests == [.reminder])
        #expect(try f.notes.load(note.id).schedules[0].link != nil)
        #expect(f.notifier.pending.isEmpty)
        f.bridge.changeExternally(item.id) { $0.start = future.addingTimeInterval(600); $0.title = "밖 제목" }
        await f.service.flush()
        var read = try f.notes.load(note.id)
        #expect(read.schedules[0].title == "밖 제목")
        #expect(read.schedules[0].start == future.addingTimeInterval(600))
        #expect(read.title == "노트 제목" && read.body == note.body)
        f.bridge.changeExternally(item.id) { $0.isCompleted = true }
        await f.service.flush()
        read = try f.notes.load(note.id)
        #expect(read.schedules[0].isCompleted)
        #expect(read.body == "[x] 원문\n다른 글")
        try f.notes.update(note.id) { $0.body = "[ ] 원문\n다른 글" }
        await f.service.flush()
        #expect(f.bridge.items[item.id]?.isCompleted == false)
        f.bridge.deleteExternally(item.id)
        await f.service.flush()
        read = try f.notes.load(note.id)
        #expect(read.schedules.isEmpty)
        #expect(read.body == "[ ] 원문\n다른 글" && read.title == "노트 제목")
    }
    @Test func editorImminenceChoiceStaysLocalAndCanFollowTheDefaultAgain() async throws {
        let f = try Fixture(); defer { f.close() }
        let item = ScheduleItem(start: future, imminentLeadMinutes: .fifteen)
        let note = try f.create(NoteDraft(schedules: [item]))
        await f.service.flush()
        let editor = try f.editor(note.id)
        #expect(editor.showsImminentLead && editor.defaultLeadLabel == "기본(30분 전)")
        editor.displayOptions.imminentLeadTime = 3600
        #expect(editor.defaultLeadLabel == "기본(1시간 전)")
        let remote = try #require(f.bridge.items[item.id])
        #expect(remote.imminentLeadMinutes == nil)
        let saves = f.bridge.saves, reads = f.bridge.reads
        editor.chooseImminentLead(.ten)
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.first?.imminentLeadMinutes == .ten)
        #expect(f.bridge.saves == saves && f.bridge.reads == reads)
        f.bridge.changeExternally(item.id) { $0.title = "바깥 수정" }
        await f.service.flush()
        editor.reload()
        #expect(editor.selectedItem?.title == "바깥 수정" && editor.selectedItem?.imminentLeadMinutes == .ten)
        editor.chooseImminentLead(nil)
        #expect(try f.notes.load(note.id).schedules.first?.imminentLeadMinutes == nil)
        editor.dateOnly = true
        #expect(editor.save() && !editor.showsImminentLead)
        editor.chooseImminentLead(.ten)
        #expect(try f.notes.load(note.id).schedules.first?.imminentLeadMinutes == nil)
        await f.service.flush()
    }

    @Test func calendarChangeSurvivesFailureAndMovesOnlySelectedItem() async throws {
        let f = try fixture()
        defer { f.close() }
        let event = ScheduleItem(start: future, end: future.addingTimeInterval(3600), title: "회의")
        let other = ScheduleItem(start: future, title: "할 일")
        let note = try f.create(NoteDraft(schedules: [event, other]))
        await f.service.flush()
        let editor = try f.editor(note.id)
        editor.select(event.id)
        f.bridge.failure = .readOnly
        editor.chooseCalendar("work")
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].pendingCalendarID == "work")
        f.bridge.failure = nil
        f.service.refreshLinked()
        await f.service.flush()
        let saved = try f.notes.load(note.id).schedules
        #expect(saved[0].pendingCalendarID == nil)
        #expect(f.bridge.destination(for: saved[0])?.name == "업무")
        #expect(f.bridge.destination(for: saved[1]) == f.bridge.reminderDestination)
        #expect(f.bridge.items.count == 2)
    }

    @Test func multipleSchedulesLocalEditAndDelete() async throws {
        let f = try fixture(); defer { f.close() }
        let first = ScheduleItem(start: future, title: "첫째")
        let event = ScheduleItem(start: future, end: future.addingTimeInterval(3600), title: "회의")
        let note = try f.create(NoteDraft(schedules: [first, event]))
        await f.service.flush()
        #expect(f.bridge.items.count == 2)
        #expect(Set(f.bridge.authorizationRequests) == [.event, .reminder])
        try f.notes.update(note.id) {
            $0.schedules[1].end = future.addingTimeInterval(7200)
            $0.schedules[1].modified = Date()
            $0.schedules[0].isDeleted = true
        }
        await f.service.flush()
        #expect(f.bridge.items[first.id] == nil)
        #expect(f.bridge.items[event.id]?.end == future.addingTimeInterval(7200))
        #expect(try f.notes.load(note.id).schedules.count == 1)
    }
    @Test func deniedFallbackAndRecoveryDoNotDuplicateNotifications() async throws {
        let f = try fixture(); defer { f.close() }
        f.bridge.failure = .readOnly
        let item = ScheduleItem(start: future, title: "알림")
        let note = try f.create(NoteDraft(body: "보존", schedules: [item]))
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].syncError != nil)
        #expect(f.notifier.pending[item.id] != nil)
        f.bridge.failure = nil
        f.service.enqueue(note.id)
        await f.service.flush()
        #expect(f.notifier.pending.isEmpty)
        #expect(try f.notes.load(note.id).schedules[0].syncError == nil)
        f.bridge.failure = .readOnly
        try f.notes.update(note.id) { $0.schedules[0].isDeleted = true }
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].link != nil)
        #expect(try f.notes.load(note.id).schedules[0].isDeleted)
        f.bridge.failure = nil
        f.service.refreshLinked()
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
        #expect(f.bridge.items.isEmpty)
    }
    @Test func unavailablePermissionIsNotExternalDeletion() async throws {
        let f = try fixture(); defer { f.close() }
        let item = ScheduleItem(start: future)
        let note = try f.create(NoteDraft(schedules: [item]))
        await f.service.flush()
        f.bridge.isAllowed = false
        f.service.refreshLinked(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.count == 1)
        #expect(f.notifier.pending.isEmpty)
    }
    @Test func latestTimestampWinsAndConflictIsRecorded() async throws {
        let f = try fixture(); defer { f.close() }
        let item = ScheduleItem(start: future, title: "원문")
        let note = try f.create(NoteDraft(body: "보존", schedules: [item]))
        await f.service.flush()
        let later = Date().addingTimeInterval(120)
        f.bridge.items[item.id]?.title = "원격 승리"
        f.bridge.items[item.id]?.modified = later
        try f.notes.update(note.id) { $0.schedules[0].title = "로컬"; $0.schedules[0].modified = Date() }
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].title == "원격 승리")
        #expect(f.logs.contains { $0.contains("충돌") })
        f.bridge.items[item.id]?.title = "원격"
        f.bridge.items[item.id]?.modified = later.addingTimeInterval(20)
        try f.notes.update(note.id) { $0.schedules[0].title = "로컬 승리"; $0.schedules[0].modified = later.addingTimeInterval(30) }
        await f.service.flush()
        #expect(f.bridge.items[item.id]?.title == "로컬 승리")
    }
    @Test func ambiguousTodoIsNeverGuessedAndDateOnlyHasNoAppAlarm() async throws {
        let f = try fixture(); defer { f.close() }
        let item = ScheduleItem(start: future, title: "일", todo: TodoAnchor(line: 0, text: "일"))
        let note = try f.create(NoteDraft(body: "[ ] 일\n[ ] 일", schedules: [item]))
        await f.service.flush()
        f.bridge.changeExternally(item.id) { $0.isCompleted = true }
        await f.service.flush()
        #expect(try f.notes.load(note.id).body == note.body)
        f.bridge.isAllowed = false
        _ = try f.create(NoteDraft(schedules: [ScheduleItem(start: future, isDateOnly: true)]))
        await f.service.flush()
        #expect(f.notifier.pending.isEmpty)
    }
    @Test func editorValidatesRangeAndPersistsMultipleItemsAndDeletion() throws {
        let f = try fixture(); defer { f.close() }
        let note = try f.create(NoteDraft(title: "제목", body: "원문"))
        let editor = try f.editor(note.id)
        editor.start = future; editor.hasEnd = true; editor.end = future
        #expect(!editor.save())
        editor.end = future.addingTimeInterval(3600)
        #expect(editor.save())
        let next = try f.editor(note.id)
        next.select(nil); next.dateOnly = true; next.start = future
        #expect(next.save())
        let read = try f.notes.load(note.id)
        #expect(read.schedules.count == 2)
        #expect(read.schedules[1].isDateOnly)
        let deletion = try f.editor(note.id)
        #expect(deletion.remove())
        #expect(try f.notes.load(note.id).schedules.contains { $0.isDeleted })
    }
    private var future: Date { Date(timeIntervalSince1970: 2_000_000_000) }
}

@MainActor private final class Fixture {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("schedule-" + UUID().uuidString)
    let notes: FileNoteStore
    let bridge = FakeCalendarBridge()
    let notifier = FakeReminderNotifier()
    var service: ScheduleService!
    var constructed = 0
    var logs: [String] = []
    init() throws {
        notes = try FileNoteStore(location: .isolated(notesDirectory: root))
        service = ScheduleService(notes: notes, notifier: notifier, makeBridge: { [unowned self] in
            constructed += 1; return bridge
        }, log: { [weak self] in self?.logs.append($0) })
        try service.start()
    }
    // 빠른 캡처/설정에서의 명시적인 신규 생성 경로를 재현한다.
    func create(_ draft: NoteDraft) throws -> Note {
        let note = try notes.create(draft)
        for item in note.schedules { service.register(note.id, itemID: item.id, requestPermission: true) }
        return note
    }
    func editor(_ id: NoteID) throws -> ReminderEditorModel {
        let editor = try ReminderEditorModel(noteID: id, notes: notes)
        editor.onSave = { [unowned self] id, itemID, isNew in
            service.register(id, itemID: itemID, requestPermission: isNew)
        }
        return editor
    }
    func close() {
        service.stop()
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("임시 폴더 정리 실패: \(error)") }
    }
}

extension ScheduleServiceTests {
    @Test func checkboxEditedDuringPermissionWaitIsNotLost() async throws {
        let f = try Fixture(); defer { f.close() }
        var continuation: CheckedContinuation<Void, Never>?
        f.bridge.authorizationGate = {
            await withCheckedContinuation { continuation = $0 }
        }
        let item = ScheduleItem(start: Date(timeIntervalSince1970: 2_000_000_000), title: "일", todo: TodoAnchor(line: 0, text: "일"))
        let note = try f.create(NoteDraft(body: "[ ] 일\n", schedules: [item]))
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let gate = try #require(continuation)
        try f.notes.update(note.id) { $0.body = "[x] 일\n추가 글" }
        f.bridge.authorizationGate = nil
        gate.resume()
        await f.service.flush()
        #expect(f.bridge.items[item.id]?.isCompleted == true)
        #expect(try f.notes.load(note.id).body == "[x] 일\n추가 글")
    }
    @Test func restartDoesNotRequestPermissionAgainAndOnlyReadsLinkedItems() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.create(NoteDraft(schedules: [ScheduleItem(start: Date(timeIntervalSince1970: 2_000_000_000))]))
        await f.service.flush()
        let requests = f.bridge.authorizationRequests
        let saves = f.bridge.saves
        f.service.stop()
        f.service = ScheduleService(notes: f.notes, notifier: f.notifier, makeBridge: { f.bridge })
        try f.service.start(); await f.service.flush()
        #expect(f.bridge.authorizationRequests == requests)
        #expect(f.bridge.saves == saves)
        #expect(try f.notes.load(note.id).schedules.count == 1)
        #expect(f.bridge.reads > 0)
    }
    @Test func convertingReminderToEventRequestsNewKindAndRetainsIdentity() async throws {
        let f = try Fixture(); defer { f.close() }
        let item = ScheduleItem(start: Date(timeIntervalSince1970: 2_000_000_000))
        let note = try f.create(NoteDraft(schedules: [item]))
        await f.service.flush()
        let editor = try f.editor(note.id)
        editor.hasEnd = true; editor.end = item.start.addingTimeInterval(3600)
        #expect(editor.save())
        await f.service.flush()
        #expect(f.bridge.authorizationRequests == [.reminder, .event])
        #expect(f.bridge.items.count == 1)
        #expect(f.bridge.items[item.id]?.kind == .event)
    }
}

extension ScheduleServiceTests {
    @Test func externalChangesWithinTheSameTimestampAreStillRead() async throws {
        let f = try Fixture(); defer { f.close() }
        let item = ScheduleItem(start: Date(timeIntervalSince1970: 2_000_000_000))
        let note = try f.create(NoteDraft(body: "원문", schedules: [item]))
        await f.service.flush()
        // EventKit 백엔드가 같은 초의 수정 시각을 돌려주는 경우.
        let sameTimestamp = f.bridge.items[item.id]!.modified
        f.bridge.items[item.id]?.start = item.start.addingTimeInterval(600)
        f.bridge.items[item.id]?.modified = sameTimestamp
        f.service.refreshLinked(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].start == item.start.addingTimeInterval(600))
    }
}


extension ScheduleServiceTests {
    @Test func legacyStartupAndAutosaveNeverRequestPermissionOrMigrateFiles() async throws {
        let f = try Fixture(); defer { f.close() }
        f.service.stop()
        f.bridge.isAllowed = false
        let id = NoteID(rawValue: "old-reminder")
        let url = f.root.appendingPathComponent("old-reminder.md")
        let raw = "---\ntitle: 옛 노트\nreminder: 2033-05-18T03:33:20Z\ncreated: 2026-11-16T00:00:00Z\n---\n본문\n"
        try raw.write(to: url, atomically: true, encoding: .utf8)
        try f.notes.refresh()
        try f.service.start(); await f.service.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == raw)
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
        #expect(f.notifier.permissionRequests == 0)
        #expect(f.constructed == 0)
        #expect(try f.notes.load(id).schedules[0].syncError == nil)
        try f.notes.scheduleUpdate(id) { $0.body += "입력" }
        try f.notes.flushPendingSaves()
        await f.service.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == raw + "입력")
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
        #expect(f.bridge.saves == 0)
        #expect(try f.notes.load(id).schedules[0].syncError == nil)
        // 밖에서 바꾼 본문도 권한 요청이나 마이그레이션을 하지 않는다.
        try (raw + "외부").write(to: url, atomically: true, encoding: .utf8)
        try f.notes.refresh(); await f.service.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == raw + "외부")
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
    }

    @Test func onlyExplicitNewItemRequestsPermissionAndDeniedItemsStayLocal() async throws {
        let f = try Fixture(); defer { f.close() }
        f.bridge.isAllowed = false
        let note = try f.notes.create(NoteDraft(body: "원문", schedules: [ScheduleItem(start: future)]))
        await f.service.flush()
        let url = f.root.appendingPathComponent(note.id.rawValue + ".md")
        let raw = try Data(contentsOf: url)
        f.service.stop(); try f.service.start(); await f.service.flush()
        #expect(try Data(contentsOf: url) == raw)
        try f.notes.update(note.id) { $0.body += "편집" }
        await f.service.flush()
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
        let editor = try f.editor(note.id)
        editor.select(nil); editor.title = "새 항목"; editor.start = future
        #expect(editor.save())
        await f.service.flush()
        #expect(f.bridge.authorizationPromptAttempts == [.reminder])
        #expect(try f.notes.load(note.id).schedules.allSatisfy { $0.link == nil && $0.syncError == nil })
        #expect(f.notifier.permissionRequests == 0 && f.notifier.pending.isEmpty)
        try f.notes.update(note.id) { $0.body += "추가 입력" }
        await f.service.flush()
        #expect(f.bridge.authorizationPromptAttempts == [.reminder])
        #expect(f.bridge.saves == 0)
    }

    @Test func grantedPermissionNeverImportsLegacyUntilSavedAndNeverImportsPastOrCompleted() async throws {
        let f = try Fixture(); defer { f.close() }
        let old = [ScheduleItem(id: "legacy-future", start: future),
                   ScheduleItem(id: "legacy-past", start: .distantPast),
                   ScheduleItem(id: "legacy-completed", start: future, isCompleted: true)]
        let note = try f.notes.create(NoteDraft(schedules: old))
        await f.service.flush()
        let editor = try f.editor(note.id)
        editor.select(nil); editor.start = future; editor.title = "새 항목"
        #expect(editor.save()); await f.service.flush()
        #expect(f.bridge.authorizationPromptAttempts == [.reminder])
        #expect(f.bridge.saves == 1)
        try f.notes.update(note.id) { $0.body = "본문 편집" }
        f.service.refreshLinked(); await f.service.flush()
        #expect(f.bridge.saves == 1)
        for id in ["legacy-past", "legacy-completed"] {
            let editor = try f.editor(note.id); editor.select(id)
            #expect(editor.save()); await f.service.flush()
            #expect(f.bridge.items[id] == nil)
        }
        let saved = try f.editor(note.id); saved.select("legacy-future")
        #expect(saved.save()); await f.service.flush()
        #expect(f.bridge.items["legacy-future"] != nil)
        #expect(f.bridge.authorizationPromptAttempts == [.reminder])
        #expect(f.bridge.items.count == 2)
    }

    @Test func savingLegacyWithoutPermissionDoesNotRequestIt() async throws {
        let f = try Fixture(); defer { f.close() }
        f.bridge.isAllowed = false
        let note = try f.notes.create(NoteDraft(reminder: future))
        let editor = try f.editor(note.id)
        #expect(editor.save()); await f.service.flush()
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
        #expect(try f.notes.load(note.id).schedules[0].syncError == nil)
        #expect(f.bridge.items.isEmpty)
    }

    @Test func transferredLinkUpdatesExistingRemoteAndRetriesPendingDeletion() async throws {
        let f = try Fixture(); defer { f.close() }
        let original = try f.create(NoteDraft(schedules: [ScheduleItem(start: future), ScheduleItem(start: future)]))
        await f.service.flush()
        let linked = try f.notes.load(original.id).schedules
        let saves = f.bridge.saves
        try FileManager.default.removeItem(at: f.root.appendingPathComponent(original.id.rawValue + ".md"))
        try f.notes.refresh()
        var moved = linked
        moved[0].id = UUID().uuidString
        moved[1].id = UUID().uuidString; moved[1].isDeleted = true
        f.bridge.failure = .readOnly
        let replacement = try f.notes.create(NoteDraft(schedules: moved))
        await f.service.flush()
        #expect(try f.notes.load(replacement.id).schedules[1].link == linked[1].link)
        #expect(try f.notes.load(replacement.id).schedules[1].isDeleted)
        f.bridge.failure = nil
        f.service.refreshLinked(); await f.service.flush()
        #expect(f.bridge.items.count == 1)
        #expect(f.bridge.saves == saves)
        f.bridge.changeExternally(linked[0].id) { $0.title = "복구 뒤 외부 수정" }
        await f.service.flush()
        #expect(try f.notes.load(replacement.id).schedules[0].id == moved[0].id)
        #expect(try f.notes.load(replacement.id).schedules[0].title == "복구 뒤 외부 수정")
        try f.notes.update(replacement.id) { $0.schedules[0].title = "복구 뒤 수정"; $0.schedules[0].modified = Date() }
        await f.service.flush()
        #expect(f.bridge.items.count == 1)
        #expect(f.bridge.items[linked[0].id]?.title == "복구 뒤 수정")
        #expect(try f.notes.load(replacement.id).schedules.count == 1)
    }
}


extension ScheduleServiceTests {
    @Test func authorizationErrorsAndRevokedAccessNeverWriteSyncErrors() async throws {
        let f = try Fixture(); defer { f.close() }
        f.bridge.authorizationFailure = .denied
        let item = ScheduleItem(start: future)
        let note = try f.create(NoteDraft(schedules: [item]))
        let url = f.root.appendingPathComponent(note.id.rawValue + ".md")
        let original = try Data(contentsOf: url)
        await f.service.flush()
        #expect(try Data(contentsOf: url) == original)
        #expect(f.bridge.saves == 0)
        #expect(f.notifier.permissionRequests == 0 && f.notifier.pending.isEmpty)
        f.bridge.authorizationFailure = nil
        // 권한 확인 뒤 실제 저장 직전 접근이 철회된 경우.
        f.bridge.failure = .denied
        f.service.enqueue(note.id); await f.service.flush()
        #expect(try Data(contentsOf: url) == original)
        #expect(try f.notes.load(note.id).schedules[0].syncError == nil)
        #expect(f.notifier.pending.isEmpty)
    }
}

extension ScheduleServiceTests {
    @Test func trashRestoresUpcomingLinksWithFreshIDsAndSkipsPast() async throws {
        let f = try fixture(); defer { f.close() }
        let past = ScheduleItem(start: .distantPast)
        let first = ScheduleItem(start: future)
        let second = ScheduleItem(start: future, end: future.addingTimeInterval(3600))
        let done = ScheduleItem(start: future, isCompleted: true)
        let note = try f.notes.create(NoteDraft(body: "원문", schedules: [past, first, second, done]))
        await f.service.flush()
        let before = try f.notes.load(note.id).schedules
        try f.notes.moveToTrash(note.id)
        #expect(f.service.removedFromTrashMove(note.id) == [.reminder, .reminder, .event])
        #expect(f.bridge.items.count == 1 && f.bridge.items[done.id] != nil)
        try f.notes.restoreFromTrash(note.id)
        await f.service.flush()
        let restored = try f.notes.load(note.id)
        #expect(restored.body == "원문" && restored.schedules.map(\.id) == before.map(\.id))
        #expect(restored.schedules[0].link == nil)
        for index in 1...2 {
            let link = try #require(restored.schedules[index].link)
            #expect(link.externalID != before[index].link?.externalID && link.localID != before[index].link?.localID)
            #expect(link.externalID.flatMap { f.bridge.items[$0] } != nil)
        }
        f.service.refreshLinked()
        await f.service.flush()
        #expect(f.bridge.items.count == 3 && f.bridge.authorizationPromptAttempts.isEmpty)
        #expect(f.notifier.permissionRequests == 0)
    }

    @Test func trashRetrySurvivesRestartAndRestoreBeforeRetryAvoidsDuplicates() async throws {
        let f = try fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(schedules: [ScheduleItem(start: future)]))
        await f.service.flush()
        f.bridge.failure = .readOnly
        try f.notes.moveToTrash(note.id)
        let pending = try #require(try f.notes.listTrash().notes.first?.schedules.first)
        #expect(pending.link != nil && pending.syncError != nil && f.service.removedFromTrashMove(note.id).isEmpty)
        f.bridge.failure = nil
        try f.notes.restoreFromTrash(note.id)
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.first?.link == pending.link)
        #expect(f.bridge.items.count == 1)
        f.bridge.isAllowed = false
        try f.notes.moveToTrash(note.id)
        f.service.stop()
        f.bridge.isAllowed = true
        f.service = ScheduleService(notes: f.notes, notifier: f.notifier, makeBridge: { f.bridge })
        try f.service.start()
        #expect(f.bridge.items.isEmpty)
        try f.notes.restoreFromTrash(note.id)
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.first?.link != pending.link)
        #expect(f.bridge.items.count == 1 && f.bridge.authorizationPromptAttempts.isEmpty)
    }

    @Test func trashCancelsAndRestoreReschedulesLocalNotificationWithoutPrompt() async throws {
        let f = try fixture(); defer { f.close() }
        f.bridge.failure = .readOnly
        let item = ScheduleItem(start: future)
        let note = try f.notes.create(NoteDraft(schedules: [item]))
        await f.service.flush()
        #expect(f.notifier.pending[item.id] != nil)
        try f.notes.moveToTrash(note.id)
        #expect(f.notifier.pending.isEmpty && f.service.removedFromTrashMove(note.id).isEmpty)
        f.bridge.isAllowed = false
        try f.notes.restoreFromTrash(note.id)
        await f.service.flush()
        #expect(f.notifier.pending[item.id] != nil)
        f.bridge.failure = nil
        f.bridge.isAllowed = true
        await f.service.flush()
        #expect(f.notifier.pending.isEmpty && f.bridge.items.count == 1)
        #expect(f.notifier.permissionRequests == 0 && f.bridge.authorizationPromptAttempts.isEmpty)
    }
}

extension ScheduleServiceTests {
    @Test func restoreOlderTrashFileSkipsPastAndCompletedAndResumesLocalAlarm() async throws {
        let f = try fixture(); defer { f.close() }
        f.bridge.isAllowed = false
        let past = ScheduleItem(start: .distantPast)
        let done = ScheduleItem(start: future, isCompleted: true)
        let next = ScheduleItem(start: future)
        let note = try f.notes.create(NoteDraft(schedules: [past, done, next]))
        await f.service.flush()
        // 과거 버전은 별도 표시 없이 원본 파일을 그대로 휴지통으로 옮겼다.
        let location = f.notes.location
        let filename = note.id.rawValue + ".md"
        try FileManager.default.moveItem(at: location.notesDirectory.appendingPathComponent(filename),
                                         to: location.trashDirectory.appendingPathComponent(filename))
        try f.notes.refresh()
        try f.notes.restoreFromTrash(note.id)
        await f.service.flush()
        #expect(Set(f.notifier.pending.keys) == [next.id])
        f.bridge.isAllowed = true
        await f.service.flush()
        #expect(Set(f.bridge.items.keys) == [next.id])
        #expect(f.notifier.pending.isEmpty && f.bridge.authorizationPromptAttempts.isEmpty)
    }
}
