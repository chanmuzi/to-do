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
    @Test func schedulePopoverDismissesOnExternalFocusAndFinishesTitleComposition() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dismissal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileNoteStore(location: .isolated(notesDirectory: root))
        let id = try store.create(NoteDraft(title: "원래 노트")).id
        _ = NSApplication.shared
        let item = ScheduleItem(start: now, title: "저장된 일정")
        try store.update(id) { $0.schedules = [item] }
        let before = try store.load(id)
        let coordinator = ReminderEditorCoordinator(notes: store, theme: try Theme.bundled())
        coordinator.allowsKeyWindows = false
        defer { coordinator.close() }
        let owner = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let anchor = try #require(owner.contentView)
        let other = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var saves = 0
        coordinator.onSave = { _, _, _ in saves += 1 }
        @MainActor func openDraft() throws {
            try coordinator.show(id, anchor: anchor)
            let model = try #require(coordinator.model)
            model.select(item.id)
            model.input = "입력 중 내일 오후 3시"
            #expect(!model.candidates.isEmpty)
        }
        try openDraft()
        let popup = try #require(coordinator.contentView?.window)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: popup)
        #expect(coordinator.model != nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        #expect(coordinator.model == nil)

        try openDraft()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: owner)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(coordinator.model == nil)

        try openDraft()
        let fieldWindow = try #require(coordinator.contentView?.window)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let content = try #require(coordinator.contentView)
        @MainActor func input(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { input(in: $0) }.first
        }
        let field = try #require(input(in: content))
        #expect(fieldWindow.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!editor.hasMarkedText())
        #expect(coordinator.contentView == nil && coordinator.model == nil)
        let updated = try store.load(id)
        #expect(updated.body == before.body)
        #expect(updated.schedules.first?.title.contains("한") == true)
        #expect(saves > 0)
    }

    @Test func titleTabOpensDateAndReturnToTimeKeepsSameEditor() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("schedule-tab-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileNoteStore(location: .isolated(notesDirectory: root))
        let item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "회의")
        let id = try store.create(NoteDraft(schedules: [item])).id
        _ = NSApplication.shared
        let owner = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let coordinator = ReminderEditorCoordinator(notes: store, theme: try Theme.bundled())
        coordinator.allowsKeyWindows = false
        defer { coordinator.close() }
        try coordinator.show(id, anchor: try #require(owner.contentView))
        let model = try #require(coordinator.model)
        model.select(item.id)
        let window = try #require(coordinator.contentView?.window)
        try await Task.sleep(for: .milliseconds(80))
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        NSApp.sendEvent(event)
        try await Task.sleep(for: .milliseconds(80))
        let panel = try #require(model.pickerWindow)
        let field = try #require(panel.firstResponder as? NSTextView)
        let input = try #require(field.delegate as? NSTextField)
        let handled = input.delegate?.control?(input, textView: field, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(handled == true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.datePicker == nil && model.selectedID == item.id)
        let time = try #require(window.firstResponder as? NSTextView)
        #expect(model.startField?.currentEditor() === time)
        NSApp.sendEvent(event)
        try await Task.sleep(for: .milliseconds(80))
        let end = try #require(window.firstResponder as? NSTextView)
        #expect(model.endField?.currentEditor() === end)
    }

    @Test func schedulePopoverOutsideClickDismissesWhileInsideClickKeepsDraft() throws {
        try fixture { _, store, id in
            let item = ScheduleItem(start: now, title: "기존 일정")
            try store.update(id) { $0.schedules = [item] }
            _ = NSApplication.shared
            let coordinator = ReminderEditorCoordinator(notes: store, theme: try Theme.bundled())
            coordinator.allowsKeyWindows = false
            defer { coordinator.close() }
            let owner = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            try coordinator.show(id, anchor: try #require(owner.contentView))
            let popup = try #require(coordinator.contentView?.window)
            coordinator.model?.input = "입력 중 내일"
            @MainActor func click(_ window: NSWindow) throws {
                // 이 앱의 창 번호를 대상으로 로컬 모니터를 거치는 오른쪽 누름을 보낸다.
                let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 1, y: 1),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                NSApp.sendEvent(event)
            }
            try click(popup)
            #expect(coordinator.model?.input == "입력 중 내일")
            try click(owner)
            #expect(coordinator.model == nil)
            #expect(try store.load(id).schedules == [item])
        }
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
    @Test func pickerNavigatesWeeksMonthsAndCommitsParsedDayToOriginalItem() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "회의")
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            model.showDates()
            let picker = try #require(model.datePicker)
            #expect(calendar.component(.weekday, from: picker.week) == 1)
            picker.scrollWeeks(3)
            #expect(calendar.component(.month, from: picker.week) == 12)
            picker.choosingMonth = true
            picker.moveHeader(1)
            #expect(calendar.component(.year, from: picker.month) == 2027)
            #expect(calendar.component(.weekday, from: picker.quickDay(2)) == 2)
            picker.input = "다음 주 금요일"
            model.applyExpression(try #require(picker.parse()))
            let saved = try #require(store.load(id).schedules.first)
            #expect(saved.id == item.id && saved.end!.timeIntervalSince(saved.start) == 3600)
            #expect(calendar.component(.weekday, from: saved.start) == 6 && calendar.component(.hour, from: saved.start) == 10)
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
