import Foundation
import Testing
import Models
import Store
import Scheduling
import DateTime

@MainActor @Suite struct InlineScheduleTests {
    @Test func acceptUpdateUndoRedoAndCompletionUseOneExternalItem() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(title: "제목", body: "[ ] 회의 내일 3시"))
        let request = f.request(body: "[ ] 회의", todo: true)
        let effect = try f.writer.accept(request, in: note.id)
        try f.notes.update(note.id) { $0.body = request.nextText }
        await f.service.flush()
        var saved = try f.notes.load(note.id)
        let item = try #require(saved.schedules.first)
        #expect(item.todo?.text == "회의")
        #expect(f.bridge.items.count == 1)
        #expect(f.bridge.authorizationPromptAttempts == [.reminder])
        f.bridge.changeExternally(item.id) { $0.isCompleted = true }
        await f.service.flush()
        #expect(try f.notes.load(note.id).body == "[x] 회의")
        try f.notes.update(note.id) { $0.body = "[ ] 회의" }
        await f.service.flush()
        #expect(f.bridge.items[item.id]?.isCompleted == false)
        let update = f.request(body: "[ ] 회의", todo: true, event: true)
        let updateEffect = try f.writer.accept(update, in: note.id)
        await f.service.flush()
        saved = try f.notes.load(note.id)
        #expect(saved.schedules.count == 1 && saved.schedules[0].id == item.id)
        #expect(saved.schedules[0].kind == .event)
        try updateEffect.undo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].value == item.value)
        #expect(f.bridge.items.count == 1)
        try effect.undo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
        #expect(f.bridge.items.isEmpty)
        try effect.redo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.count == 1)
        #expect(f.bridge.items.count == 1)
    }
    @Test func titleUpdatesItsOwnItemWithoutTodoAndDoesNotTouchOtherSchedules() async throws {
        let f = try Fixture(); defer { f.close() }
        let other = ScheduleItem(start: f.future, title: "별도")
        let note = try f.notes.create(NoteDraft(title: "회의 내일", body: "본문", schedules: [other]))
        let first = f.request(body: "회의", line: nil)
        let effect = try f.writer.accept(first, in: note.id)
        await f.service.flush()
        let initial = try f.notes.load(note.id).schedules.last!
        let second = f.request(body: "바꾼 제목", line: nil, event: true)
        let update = try f.writer.accept(second, in: note.id)
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.count == 2)
        #expect(try f.notes.load(note.id).schedules.last?.id == initial.id)
        #expect(try f.notes.load(note.id).schedules.last?.todo == nil)
        try update.undo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.last?.value == initial.value)
        try effect.undo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.map(\.id) == [other.id])
        #expect(try f.notes.load(note.id).body == "본문")
    }
    @Test func immediateUndoDuringPermissionWaitNeverCreatesRemote() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(body: "회의 내일"))
        var continuation: CheckedContinuation<Void, Never>?
        f.bridge.authorizationGate = { await withCheckedContinuation { continuation = $0 } }
        let effect = try f.writer.accept(f.request(body: "회의"), in: note.id)
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let gate = try #require(continuation)
        try effect.undo()
        f.bridge.authorizationGate = nil
        gate.resume()
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
        #expect(f.bridge.items.isEmpty && f.notifier.pending.isEmpty)
    }
    @Test func deletionFailureRetainsLinkAndRetries() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(body: "회의"))
        let effect = try f.writer.accept(f.request(body: "회의"), in: note.id)
        await f.service.flush()
        f.bridge.failure = .readOnly
        try effect.undo(); await f.service.flush()
        let pending = try #require(f.notes.load(note.id).schedules.first)
        #expect(pending.isDeleted && pending.link != nil)
        f.bridge.failure = nil
        f.service.refreshLinked(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
        #expect(f.bridge.items.isEmpty)
    }
    @Test func deniedPermissionKeepsLocalAndUndoRemovesIt() async throws {
        let f = try Fixture(); defer { f.close() }
        f.bridge.isAllowed = false
        let note = try f.notes.create(NoteDraft(body: "회의"))
        let effect = try f.writer.accept(f.request(body: "회의"), in: note.id)
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.count == 1)
        #expect(f.bridge.items.isEmpty && f.notifier.permissionRequests == 0)
        try effect.undo(); await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
    }
    @Test func editingAndMovingTheLineKeepsTheScheduleIdentity() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(body: "[ ] 회의"))
        _ = try f.writer.accept(f.request(body: "[ ] 회의", todo: true), in: note.id)
        await f.service.flush()
        let id = try #require(f.notes.load(note.id).schedules.first?.id)
        try f.notes.update(note.id) { $0.body = "[ ] 바뀐 회의" }
        try f.notes.update(note.id) { $0.body = "윗줄\n" + $0.body }
        try f.notes.update(note.id) { $0.body += " 내일 3시" }
        let updated = try f.notes.load(note.id)
        #expect(updated.schedules[0].inlineSource?.line == 1)
        let request = InlineDateAcceptance(item: ScheduleItem(start: f.future.addingTimeInterval(7200)),
            source: InlineScheduleSource(line: 1, text: "[ ] 바뀐 회의"), todo: TodoAnchor(line: 1, text: "바뀐 회의"),
            previousText: updated.body, nextText: "윗줄\n[ ] 바뀐 회의")
        _ = try f.writer.accept(request, in: note.id)
        try f.notes.update(note.id) { $0.body = request.nextText }
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.map(\.id) == [id])
        #expect(f.bridge.items.count == 1)
        f.bridge.changeExternally(id) { $0.isCompleted = true }
        await f.service.flush()
        #expect(try f.notes.load(note.id).body == "윗줄\n[x] 바뀐 회의")
    }
    @Test func expressionOnlyLineCanBecomeEmptyWithoutBindingAnotherBlank() async throws {
        let f = try Fixture(); defer { f.close() }
        let note = try f.notes.create(NoteDraft(body: "\n내일\n"))
        let request = InlineDateAcceptance(item: ScheduleItem(start: f.future),
            source: InlineScheduleSource(line: 1, text: ""), todo: nil, previousText: "\n내일\n", nextText: "\n\n")
        _ = try f.writer.accept(request, in: note.id)
        try f.notes.update(note.id) { $0.body = request.nextText }
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules[0].inlineSource?.line == 1)
    }

    @Test func editorDeletionRestoresMultipleLineKindsAndFreshExternalLinks() async throws {
        let f = try Fixture(); defer { f.close() }
        let lines = ["[ ] 확인", "- 글머리표", "일반 줄", "남길 줄"]
        let body = lines.joined(separator: "\n")
        let items = lines.prefix(3).enumerated().map { line, text in
            ScheduleItem(start: f.future, end: line == 2 ? f.future.addingTimeInterval(3600) : nil,
                         title: text, todo: TodoAnchor(line: line, sourceLine: text),
                         inlineSource: InlineScheduleSource(line: line, text: text))
        }
        let title = ScheduleItem(start: f.future, inlineSource: InlineScheduleSource(line: nil, text: "제목"))
        var linked = items
        for index in linked.indices {
            let oldID = "old-" + linked[index].id
            linked[index].link = .init(localID: oldID, externalID: oldID, kind: linked[index].kind)
            f.bridge.items[oldID] = linked[index]
        }
        let note = try f.notes.create(NoteDraft(title: "제목", body: body, schedules: linked + [title]))
        await f.service.flush()
        let deletion = try #require(try f.writer.removeMissingSources(from: body, to: "남길 줄", in: note.id))
        #expect(deletion.items.map(\.id) == items.map(\.id))
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.map(\.id) == [title.id])
        #expect(f.bridge.items.count == 1)
        try deletion.effect.undo()
        try f.notes.scheduleUpdate(note.id) { $0.body = body }
        await f.service.flush()
        let restored = try f.notes.load(note.id)
        for item in items {
            let copy = try #require(restored.schedules.first { $0.id == item.id })
            let newID = try #require(copy.link?.externalID)
            #expect(newID != "old-" + item.id && f.bridge.items[newID] != nil)
            #expect(copy.inlineSource == item.inlineSource && copy.todo == item.todo)
        }
        try deletion.effect.redo()
        try f.notes.scheduleUpdate(note.id) { $0.body = "남길 줄" }
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.map(\.id) == [title.id])
        #expect(f.bridge.authorizationPromptAttempts.isEmpty)
    }

    @Test func ambiguousAndOutsideEditsOnlyDetachAndPasteDoesNotRestore() async throws {
        let f = try Fixture(); defer { f.close() }
        let item = ScheduleItem(start: f.future, inlineSource: InlineScheduleSource(line: 0, text: "회의"))
        let note = try f.notes.create(NoteDraft(body: "회의\n회의", schedules: [item]))
        #expect(try f.writer.removeMissingSources(from: "회의\n회의", to: "회의", in: note.id) == nil)
        #expect(try f.notes.load(note.id).schedules.first?.inlineSource == nil)
        try f.notes.update(note.id) { $0.body = "회의\n아래"; $0.schedules = [item] }
        try f.notes.update(note.id) { $0.body = "아래" }
        #expect(try f.notes.load(note.id).schedules.first?.isDeleted == false)
        #expect(try f.writer.removeMissingSources(from: "회의\n아래", to: "아래", in: note.id) == nil)
        try f.notes.update(note.id) { $0.body = "회의"; $0.schedules = [item] }
        await f.service.flush()
        f.bridge.failure = .readOnly
        _ = try #require(try f.writer.removeMissingSources(from: "회의", to: "", in: note.id))
        await f.service.flush()
        let pending = try #require(f.notes.load(note.id).schedules.first)
        #expect(pending.isDeleted && pending.link != nil && pending.syncError != nil)
        try f.notes.update(note.id) { $0.body = "회의" }
        f.bridge.failure = nil
        f.service.refreshLinked()
        await f.service.flush()
        #expect(try f.notes.load(note.id).schedules.isEmpty)
    }

    private final class Fixture {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let future = Date(timeIntervalSince1970: 2_000_000_000)
        let notes: FileNoteStore
        let bridge = FakeCalendarBridge()
        let notifier = FakeReminderNotifier()
        let service: ScheduleService
        let writer: InlineScheduleWriter
        init() throws {
            notes = try FileNoteStore(location: .isolated(notesDirectory: root))
            let bridge = bridge
            service = ScheduleService(notes: notes, notifier: notifier, makeBridge: { bridge })
            writer = InlineScheduleWriter(notes: notes, service: service)
            try service.start()
        }
        func request(body: String, line: Int? = 0, todo: Bool = false, event: Bool = false) -> InlineDateAcceptance {
            InlineDateAcceptance(item: ScheduleItem(start: future, end: event ? future.addingTimeInterval(3600) : nil),
                source: InlineScheduleSource(line: line, text: body), todo: todo ? TodoAnchor(line: 0, text: "회의") : nil,
                previousText: body + " 내일 3시", nextText: body)
        }
        func close() {
            service.stop()
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record("정리 실패: \(error)") }
        }
    }
}
