import AppKit
import SwiftUI
import Foundation
import Testing
import FieldTestSupport
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
    @Test func listRowHeightAndTimeFont() throws {
        let theme = try Theme.bundled()
        #expect(theme.component(.scheduleRowHeight) == 42)
        #expect(theme.nsFont(.scheduleTime).pointSize == 11.5)
        #expect(theme.nsFont(.scheduleTime).familyName == theme.nsFont(.body).familyName)
    }

    @Test func listKeepsOnlyRemindersCompletedDuringThisPresentation() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now, title: "연결", todo: TodoAnchor(line: 0, text: "연결"))
            let done = ScheduleItem(start: now, isCompleted: true)
            let event = ScheduleItem(start: now, end: now.addingTimeInterval(3600))
            try store.update(id) { $0.body = "[ ] 연결"; $0.schedules = [item, done, event] }
            model.reload()
            model.toggleCompleted(event.id)
            model.toggleCompleted(item.id)
            #expect(Set(model.listItems.map(\.id)) == [item.id, event.id])
            #expect(try store.load(id).body == "[x] 연결")
            model.toggleCompleted(item.id)
            #expect(try store.load(id).body == "[ ] 연결")
            try store.update(id) { $0.schedules.removeAll { $0.id == event.id } }
            model.toggleCompleted(item.id)
            #expect(model.listItems.map(\.id) == [item.id])
            #expect(try store.load(id).displayedSchedule(at: now) == nil)
            let reopened = try ReminderEditorModel(noteID: id, notes: store)
            #expect(reopened.listItems.isEmpty)
        }
    }

    @Test func imminentMenuShowsTheCurrentDefaultAndSavesTheSelectedValue() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now)
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            model.displayOptions.imminentLeadTime = 3600
            let host = NSHostingView(rootView: ScheduleDetail(model: model, item: item, theme: try Theme.bundled()))
            let window = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                                 backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            @MainActor func find(_ view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.accessibilityLabel() == "임박 표시" { return button }
                return view.subviews.lazy.compactMap(find).first
            }
            let button = try #require(find(host))
            let menu = try #require(button.menu)
            #expect(button.title == "기본(1시간 전)")
            #expect(menu.items.map(\.title) == ["기본(1시간 전)", "", "10분 전", "15분 전", "30분 전", "1시간 전"])
            #expect(menu.items[1].isSeparatorItem && menu.items[0].state == .on)
            menu.performActionForItem(at: 3)
            #expect(try store.load(id).schedules.first?.imminentLeadMinutes == .fifteen)
            menu.performActionForItem(at: 0)
            #expect(try store.load(id).schedules.first?.imminentLeadMinutes == nil)
        }
    }

    @Test func scheduleFieldGeometry() throws {
        _ = FontRegistrar.registerBundledFonts()
        try fixture { model, store, id in
            let item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "")
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            let theme = try Theme.bundled()
            try FieldGeometry.verifyHosted(NSHostingView(rootView: ScheduleDetail(model: model, item: item, theme: theme)),
                                           labels: ["제목"])
            let state = ScheduleDateSelection(selected: now, now: now, calendar: calendar)
            try FieldGeometry.verifyHosted(NSHostingView(rootView: ScheduleDatePicker(state: state, model: model, theme: theme)),
                                           labels: ["날짜를 입력하세요"])
        }
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

    @Test func calendarPopupUsesSharedRowsAndKeepsTheSelectedID() throws {
        try fixture { model, store, id in
            let item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "회의")
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            let bridge = FakeCalendarBridge()
            model.calendarChoices = bridge.writableChoices(for:)
            model.destination = bridge.destination(for:)
            let theme = try Theme.bundled()
            let host = NSHostingView(rootView: ReminderEditorView(model: model, theme: theme, close: {}))
            let window = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            @MainActor func calendarButton(in view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.accessibilityLabel() == "캘린더" { return button }
                return view.subviews.lazy.compactMap(calendarButton).first
            }
            let menu = try #require(calendarButton(in: host)?.menu)
            let rows = menu.items.compactMap { $0.view as? PickerMenuRow }
            #expect(rows.count == 4 && rows.allSatisfy { $0.frame.height == 28 && $0.textFont.pointSize == 13 })
            #expect(menu.items.first { $0.title == "개인 일정" }?.state == .on)
            #expect(menu.items.filter(\.isSeparatorItem).allSatisfy { $0.view is MenuSeparatorView })
            menu.performActionForItem(at: menu.indexOfItem(withTitle: "업무"))
            #expect(try store.load(id).schedules.first?.pendingCalendarID == "work")
        }
    }

    @Test func detailRowCentersMatchTheirLabelsAndAccessories() throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        try fixture { model, store, id in
            let midnight = calendar.startOfDay(for: now)
            let item = ScheduleItem(start: midnight, end: midnight.addingTimeInterval(3600), title: "정렬",
                                    todo: .init(line: 0, text: "원문"))
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            let host = NSHostingView(rootView: ReminderEditorView(model: model, theme: try Theme.bundled(), close: {}))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            let start = try #require(model.startField)
            let end = try #require(model.endField)
            let startRect = start.convert(start.bounds, to: host)
            let endRect = end.convert(end.bounds, to: host)
            let range = startRect.union(endRect)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: range))
            host.cacheDisplay(in: range, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / range.width
            let ink = (0..<bitmap.pixelsWide).filter { x in
                (0..<bitmap.pixelsHigh).contains { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.alphaComponent * (1 - color.redComponent) > 0.29
                }
            }
            let startEdge = Int((startRect.width * scale).rounded())
            let endEdge = Int(((endRect.minX - range.minX) * scale).rounded())
            let lastStart = try #require(ink.last { $0 < startEdge })
            let separator = ink.filter { $0 >= startEdge && $0 < endEdge }
            let firstMark = try #require(separator.first)
            let lastMark = try #require(separator.last)
            let firstEnd = try #require(ink.first { $0 >= endEdge })
            let left = CGFloat(firstMark - lastStart - 1) / scale
            let right = CGFloat(firstEnd - lastMark - 1) / scale
            let gap = try Theme.bundled().space(.sp2)
            print("시간 범위 간격", left, right)
            #expect(left == gap && right == gap)
            let centers = model.previewCenters
            print("행 중심", centers)
            for (icon, label) in [("titleDot", "title"), ("clock", "~"), ("sun.max", "종일"), ("sun.max", "switch"),
                                  ("calendar", "calendarValue"), ("timer", "임박 표시"), ("timer", "leadValue"),
                                  ("text.alignleft", "본문 1번째 줄")] {
                let first = try #require(centers[icon])
                let second = try #require(centers[label])
                #expect(abs(first - second) <= 0.5, "\(icon), \(label)")
            }
        }
    }

    @Test func timeFieldsUseNativeSegmentsAndLinkInBothDirections() throws {
        _ = NSApplication.shared
        _ = FontRegistrar.registerBundledFonts()
        try fixture { model, store, id in
            let item = ScheduleItem(start: now, end: now.addingTimeInterval(3600), title: "회의")
            try store.update(id) { $0.schedules = [item] }
            model.reload()
            model.select(item.id)
            let theme = try Theme.bundled()
            let host = NSHostingView(rootView: ReminderEditorView(model: model, theme: theme, close: {}))
            let size = host.fittingSize
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            let start = try #require(model.startField)
            let end = try #require(model.endField)
            #expect(start.nextValidKeyView === end && end.previousValidKeyView === start)
            #expect(start.previousValidKeyView === start.exit && end.nextValidKeyView === end.exit)
            #expect(size.width == 280)
            let title = try #require(FieldGeometry.fields(in: host).first)
            for field: NSControl in [title, start, end] {
                let rect = field.convert(field.bounds, to: host)
                let cap = rect.minY + field.firstBaselineOffsetFromTop - (field.font?.capHeight ?? 0) / 2
                let center: CGFloat = field === title ? 52 : 82
                print("상세 정렬", field.accessibilityLabel() ?? "", rect, cap, center)
                #expect(abs(cap - center) <= 0.5)
                #expect(host.bounds.contains(rect))
            }
            for field in [start, end] {
                #expect(field.locale?.identifier == ScheduleDateSelection.displayLocale.identifier)
                #expect(field.locale?.language.languageCode == "ko")
                #expect(field.datePickerStyle == .textField && field.datePickerElements == .hourMinute)
                #expect(!field.isBordered && !field.isBezeled && !field.drawsBackground && field.font?.pointSize == 13)
            }
            model.showDates()
            model.tabFromDate(backward: false)
            #expect(model.datePicker == nil && model.selectedID == item.id)
            let later = now.addingTimeInterval(1800)
            start.dateValue = later
            start.sendAction(start.action, to: start.target)
            #expect(try store.load(id).schedules.first?.end == later.addingTimeInterval(3600))
            end.dateValue = now
            end.sendAction(end.action, to: end.target)
            #expect(model.error != nil)
            #expect(try store.load(id).schedules.first?.end == later.addingTimeInterval(3600))
            end.dateValue = later.addingTimeInterval(7200)
            end.sendAction(end.action, to: end.target)
            #expect(model.error == nil)
            #expect(try store.load(id).schedules.first?.end == end.dateValue)
        }
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
            try store.update(id) { $0.body = "+ ### 제목 토글" }
            model.input = "내일 5pm"
            #expect(model.candidates.first?.title == "제목 토글")
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
