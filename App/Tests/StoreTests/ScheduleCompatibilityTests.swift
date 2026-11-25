import Foundation
import Testing
import Models
@testable import Store

@Suite @MainActor struct ScheduleCompatibilityTests {
    @Test func legacyArchiveCanBeRestoredAndArchivedWithoutChangingBodyOrUnknownFields() throws {
        let temp = TemporaryStore()
        defer { temp.cleanUp() }
        try FileManager.default.createDirectory(at: temp.location.notesDirectory, withIntermediateDirectories: true)
        let raw = "---\ncreated: 2001-01-01\ncustom: keep\n---\n- [x] 완료\n"
        let url = temp.noteFile("old")
        try raw.write(to: url, atomically: true, encoding: .utf8)
        let store = try FileNoteStore(location: temp.location)
        let id = NoteID(rawValue: "old")
        #expect(try store.load(id).isArchived)
        #expect(try String(contentsOf: url, encoding: .utf8) == raw)
        try store.update(id) { $0.isArchived = false }
        let reloaded = try FileNoteStore(location: temp.location)
        #expect(try !reloaded.load(id).isArchived)
        try reloaded.update(id) { $0.isArchived = true }
        #expect(try reloaded.load(id).body == "- [x] 완료\n")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("custom: keep"))
        #expect(try reloaded.listTrash().notes.isEmpty)
    }

    @Test func actualStage5DecoderCanReadAndRewriteNewScheduleFiles() throws {
        let temp = TemporaryStore(); defer { temp.cleanUp() }
        let store = try FileNoteStore(location: temp.location)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let items = [ScheduleItem(start: start, imminentLeadMinutes: .fifteen, title: "알림"),
                     ScheduleItem(start: start, end: start.addingTimeInterval(3600), title: "일정")]
        let note = try store.create(NoteDraft(title: "제목", body: "[ ] 원문\n", schedules: items))
        let raw = try String(contentsOf: temp.noteFile(note.id.rawValue), encoding: .utf8)
        #expect(raw.contains(#""imminentLeadMinutes":15"#))
        #expect(raw.components(separatedBy: "imminentLeadMinutes").count == 2)
        let unknown = raw.replacingOccurrences(of: #""imminentLeadMinutes":15"#, with: #""imminentLeadMinutes":99"#)
        let forward = try #require(NoteFileCodec.decode(unknown).schedules)
        #expect(forward.count == items.count && forward[0].imminentLeadMinutes == nil)
        var old = LegacyNoteFileCodec.decode(raw)
        #expect(old.title == note.title && old.body == note.body)
        #expect(old.reminder == start)
        #expect(old.unknownLines.contains { $0.hasPrefix("schedules:") })
        old.title = "옛 앱에서 제목 수정"
        let rewritten = LegacyNoteFileCodec.encode(old, over: raw)
        let modern = NoteFileCodec.decode(rewritten)
        #expect(modern.schedules == items)
        #expect(modern.schedules?.last?.imminentLeadMinutes == nil)
        #expect(modern.body == note.body)
        #expect(modern.title == old.title)
    }
    @Test func changingTheLeadKeepsUnrecognizedScheduleFieldsByID() throws {
        let temp = TemporaryStore(); defer { temp.cleanUp() }
        let store = try FileNoteStore(location: temp.location)
        let item = ScheduleItem(start: Date(), title: "알림")
        let note = try store.create(NoteDraft(schedules: [item]))
        let url = temp.noteFile(note.id.rawValue)
        let original = try String(contentsOf: url, encoding: .utf8)
        try original.replacingOccurrences(of: "schedules: [{", with: #"schedules: [{"future":{"code":7},"#)
            .write(to: url, atomically: true, encoding: .utf8)
        let reopened = try FileNoteStore(location: temp.location)
        try reopened.update(note.id) { $0.schedules[0].imminentLeadMinutes = .ten }
        #expect(try String(contentsOf: url, encoding: .utf8).contains(#""future":{"code":7}"#))
        try reopened.update(note.id) { $0.schedules[0].imminentLeadMinutes = nil }
        let reset = try String(contentsOf: url, encoding: .utf8)
        #expect(!reset.contains("imminentLeadMinutes") && reset.contains(#""future":{"code":7}"#))
    }

    @Test func legacyReminderMigratesWithStableIdentityAndPreservesUnknownHeader() throws {
        let temp = TemporaryStore(); defer { temp.cleanUp() }
        let store = try FileNoteStore(location: temp.location)
        let note = try store.create(NoteDraft(title: "제목", reminder: Date(timeIntervalSince1970: 2_000_000_000)))
        let a = try store.load(note.id), b = try store.load(note.id)
        #expect(a.schedules.count == 1 && a.schedules[0].id == b.schedules[0].id)
        try store.update(note.id) { $0.body = "본문" }
        #expect(try store.load(note.id).schedules == a.schedules)
    }
}

extension ScheduleCompatibilityTests {
    @Test func completedScheduleOnlyNoteCannotLookBlankToStage5() throws {
        let temp = TemporaryStore(); defer { temp.cleanUp() }
        let store = try FileNoteStore(location: temp.location)
        let note = try store.create(NoteDraft(schedules: [ScheduleItem(start: Date(), isCompleted: true)]))
        try store.update(note.id) { $0.schedules[0].title = "완료" }
        let old = LegacyNoteFileCodec.decode(try String(contentsOf: temp.noteFile(note.id.rawValue), encoding: .utf8))
        // 5단계 isBlank의 정확한 조건: title/body 공백 + reminder 없음.
        #expect(!(old.title.allSatisfy(\.isWhitespace) && old.body.allSatisfy(\.isWhitespace) && old.reminder == nil))
    }
}
