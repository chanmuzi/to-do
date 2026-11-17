import AppKit
import SwiftUI
import Foundation
import Testing
import Models
import Store
import Theme
import Scheduling
@testable import Reminders

@Suite(.serialized) @MainActor struct ReminderCandidateTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10))! }
    func fixture(_ run: (ReminderEditorModel, FileNoteStore, NoteID) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("candidate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileNoteStore(location: .isolated(notesDirectory: root))
        let note = try store.create(NoteDraft(title: "원래 노트", body: "원문"))
        let date = now
        let model = try ReminderEditorModel(noteID: note.id, notes: store, calendar: calendar, now: { date })
        model.select(nil)
        try run(model, store, note.id)
    }
    @Test func singleTimeOffersHourEventAndReminderAndArrowsChoose() throws {
        try fixture { model, store, id in
            model.input = "윤부일 내일 2pm"
            #expect(model.candidates.map(\.kind) == [.event, .reminder])
            #expect(model.candidates[0].end!.timeIntervalSince(model.candidates[0].start) == 3600)
            #expect(model.candidates.allSatisfy { $0.title == "윤부일" })
            #expect(!model.expressionRanges.isEmpty)
            model.moveCandidate(1); #expect(model.candidateIndex == 1)
            model.moveCandidate(1); #expect(model.candidateIndex == 1)
            #expect(model.submitCandidate())
            let note = try store.load(id)
            #expect(note.schedules.count == 1 && note.schedules[0].kind == .reminder)
            #expect(note.body == "원문" && note.title == "원래 노트")
        }
    }
    @Test func rangesOfferOneEventAndDatesOfferAllDayAndReminder() throws {
        try fixture { model, _, _ in
            model.input = "회의 내일 2pm~4pm"
            #expect(model.candidates.count == 1 && model.candidates.first?.kind == .event)
            model.input = "휴가 내일"
            #expect(model.candidates.map(\.kind) == [.event, .reminder])
            #expect(model.candidates.allSatisfy { $0.isDateOnly })
            #expect(model.candidates[0].start == calendar.startOfDay(for: model.candidates[0].start))
            #expect(calendar.dateComponents([.day], from: model.candidates[0].start, to: model.candidates[0].end!).day == 1)
            model.input = "휴가 2026년 11월 20일~2026년 11월 22일"
            #expect(model.candidates.count == 1)
            #expect(calendar.component(.day, from: model.candidates[0].end!) == 23)
        }
    }
    @Test func selectingThenReturningUpdatesSameItemAndRetainsLink() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now.addingTimeInterval(3600), title: "회의", link: .init(localID: "a", externalID: "b", kind: .reminder))
            try store.update(id) { $0.schedules = [item, ScheduleItem(start: now.addingTimeInterval(7200), title: "보존")] }
            model.reload(); model.select(item.id)
            #expect(model.input.contains("회의 2026년 11월 18일 오전 11:00"))
            #expect(model.candidateIndex == 1)
            model.input = "수정 내일 3pm"
            var request: Bool?
            model.onSave = { _, _, creates in request = creates }
            #expect(model.submitCandidate())
            let values = try store.load(id).schedules
            #expect(values.count == 2 && values[0].id == item.id && values[0].link == item.link)
            #expect(values[0].title == "수정" && values[1].title == "보존")
            #expect(request == false)
            model.select(item.id); model.candidateIndex = 0
            #expect(model.submitCandidate()); #expect(request == true)
        }
    }
    @Test func allDaySelectionRoundTripsAndCompletionChangesLinkedTodo() throws {
        try fixture { model, store, id in
            model.input = "휴가 내일"; #expect(model.submitCandidate())
            let item = try #require(store.load(id).schedules.first)
            model.select(item.id); #expect(model.submitCandidate())
            #expect(try store.load(id).schedules[0].value == item.value)
            let todo = ScheduleItem(start: now, title: "할 일", todo: .init(line: 0, text: "할 일"))
            try store.update(id) { $0.body = "[ ] 할 일"; $0.schedules.append(todo) }
            model.reload(); model.toggleCompleted(todo.id)
            #expect(try store.load(id).body == "[x] 할 일")
            model.toggleCompleted(todo.id); #expect(try store.load(id).body == "[ ] 할 일")
            model.select(todo.id); #expect(model.remove())
            #expect(try store.load(id).schedules.last?.isDeleted == true)
        }
    }
    @Test func metadataDoesNotRequestAccessAndUsesLinkedTargetOrFallback() throws {
        let bridge = FakeCalendarBridge()
        let event = ScheduleItem(start: now, end: now.addingTimeInterval(3600))
        let reminder = ScheduleItem(start: now)
        #expect(bridge.destination(for: event)?.name == "개인 일정")
        #expect(bridge.destination(for: reminder)?.color != nil)
        var linked = reminder; linked.link = .init(localID: "list", externalID: nil, kind: .reminder)
        bridge.linkedDestinations["list"] = .init(name: "업무")
        #expect(bridge.destination(for: linked)?.name == "업무")
        #expect(bridge.destination(for: linked)?.color == nil)
        bridge.isAllowed = false
        #expect(bridge.destination(for: event) == nil && bridge.destination(for: reminder) == nil)
        #expect(bridge.authorizationRequests.isEmpty && bridge.authorizationPromptAttempts.isEmpty)
        #expect(bridge.reads == 0 && bridge.saves == 0)
        #expect(ScheduleMarker.fallback(for: .event) == .text)
        #expect(ScheduleMarker.fallback(for: .reminder) == .text2)
    }
    @Test func existingTitleContainingADateDoesNotReplaceItsScheduledDate() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now.addingTimeInterval(3600), title: "내일 할 일을 검토")
            try store.update(id) { $0.schedules = [item] }
            model.reload(); model.select(item.id)
            #expect(model.submitCandidate())
            let saved = try store.load(id).schedules[0]
            #expect(saved.start == item.start && saved.title == item.title && saved.id == item.id)
        }
    }
    @Test(arguments: ["윤부일 내일 2pm", "내일 윤부일 2pm", "윤부일 내일 2pm~4pm", "윤부일 내일"])
    func candidateTitlesUseRemainingInputForEveryKind(input: String) throws {
        try fixture { model, _, _ in
            model.input = input
            #expect(!model.candidates.isEmpty)
            #expect(model.candidates.allSatisfy { $0.title == "윤부일" })
        }
    }
    @Test func dateOnlyInputFallsBackToNoteTitleThenBodyAndPersistsThatTitle() throws {
        try fixture { model, store, id in
            model.input = "내일 2pm"
            #expect(model.candidates.allSatisfy { $0.title == "원래 노트" })
            model.chooseCandidate(1)
            #expect(model.submitCandidate())
            #expect(try store.load(id).schedules.last?.title == "원래 노트")
            try store.update(id) { $0.title = ""; $0.body = "본문 첫 줄\n사용하지 않는 둘째 줄" }
            model.input = "내일 3pm"
            #expect(model.candidates.allSatisfy { $0.title == "본문 첫 줄" })
            #expect(model.submitCandidate())
            #expect(try store.load(id).schedules.last?.title == "본문 첫 줄")
            try store.update(id) { $0.body = "" }
            model.input = "내일 4pm"
            #expect(model.candidates.allSatisfy { $0.title.isEmpty })
        }
    }
    @Test func candidateAccessibilityHasKindTitleAndSharedTimeInThatOrder() throws {
        try fixture { model, _, _ in
            model.input = "윤부일 내일 2pm"
            let labels = model.candidates.map { model.presentation($0).accessibilityLabel(title: $0.title) }
            #expect(labels == ["일정 윤부일 내일 오후 2:00~3:00", "리마인더 윤부일 내일 오후 2:00"])
            model.displayOptions.dateFormat = .absolute
            #expect(model.presentation(model.candidates[0]).accessibilityLabel(title: "윤부일") == "일정 윤부일 11월 19일 오후 2:00~3:00")
        }
    }
    @Test func renderedCandidateRowsChangeWhenOnlyTheInputTitleChanges() throws {
        try fixture { model, _, _ in
            _ = NSApplication.shared
            _ = FontRegistrar.registerBundledFonts()
            let theme = try Theme.bundled()
            // 입력 칸을 제외한 후보 영역을 비교해 제목을 종류 이름으로 하드코딩하는 회귀를 잡는다.
            @MainActor func candidatesImage(_ text: String) throws -> Data {
                model.input = text
                let view = NSHostingView(rootView: ReminderEditorView(model: model, theme: theme, close: {}))
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.layoutSubtreeIfNeeded()
                let top = theme.space(.sp3) + theme.component(.reminderInputHeight) + theme.space(.sp2)
                let height = CGFloat(model.candidates.count) * theme.component(.scheduleRowHeight)
                let rect = NSRect(x: 0, y: view.isFlipped ? top : view.bounds.height - top - height,
                                  width: view.bounds.width, height: height)
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: rect))
                view.cacheDisplay(in: rect, to: bitmap)
                return try #require(bitmap.representation(using: .png, properties: [:]))
            }
            let first = try candidatesImage("윤부일 내일 2pm")
            let second = try candidatesImage("회의 준비 내일 2pm")
            #expect(first != second)
        }
    }
    @Test func emptyPastAndDeletedItemCannotCreateAccidentally() throws {
        try fixture { model, store, id in
            model.input = "날짜 없는 글"; #expect(model.candidates.isEmpty && !model.submitCandidate())
            model.input = "2026년 11월 17일 3pm"; #expect(model.candidates.isEmpty)
            model.input = "내일 3pm"; #expect(model.submitCandidate())
            let item = try #require(store.load(id).schedules.first)
            model.select(item.id)
            try store.update(id) { $0.schedules = [] }
            #expect(!model.submitCandidate())
            #expect(try store.load(id).schedules.isEmpty)
        }
    }
}
