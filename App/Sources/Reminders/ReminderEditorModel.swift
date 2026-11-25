import AppKit
import SwiftUI
import Observation
import Models
import Store
import Theme
import DateTime

@MainActor @Observable
public final class ReminderEditorModel {
    public let noteID: NoteID
    public private(set) var items: [ScheduleItem] = []
    private var completedInList: Set<String> = []
    var listItems: [ScheduleItem] { items.filter { !$0.isCompleted || completedInList.contains($0.id) } }
    #if DEBUG
    package var previewCompletionHoverID: String?
    #endif
    public var selectedID: String?
    public var input = "" { didSet { if input != oldValue { rebuildCandidates() } } }
    public private(set) var candidates: [ScheduleItem] = []
    public private(set) var expressionRanges: [NSRange] = []
    public var candidateIndex = 0
    public private(set) var focusToken = 0
    public func chooseCandidate(_ index: Int) { candidateIndex = index; focusToken += 1 }
    public var displayOptions = NoteDisplayOptions()
    public var calendarChoices: (ScheduleItem.Kind) -> [CalendarChoice] = { _ in [] }
    @ObservationIgnored weak var pickerAnchor: NSView?
    @ObservationIgnored public weak var pickerWindow: NSWindow?
    func applyExpression(_ expression: DateTimeExpression) {
        if expression.isDateOnly && expression.end == nil { changeDay(expression.start); return }
        let duration = end.timeIntervalSince(start)
        start = expression.start
        dateOnly = expression.isDateOnly
        if let last = expression.end { end = last; hasEnd = true }
        else { end = start.addingTimeInterval(duration > 0 ? duration : 3600) }
        if save() { datePicker = nil }
    }
    public var datePicker: ScheduleDateSelection?
    public var selectedItem: ScheduleItem? { items.first { $0.id == selectedID } }
    @ObservationIgnored weak var startField: NSTextField?
    @ObservationIgnored weak var endField: NSTextField?

    func focusTime(isEnd: Bool) {
        let field = isEnd ? endField : startField
        DispatchQueue.main.async { [weak field] in
            if let field { field.window?.makeFirstResponder(field) }
        }
    }

    var tabDestination: Bool?
    func tabFromDate(backward: Bool) {
        datePicker = nil
        tabDestination = backward
    }
    public func showDates() { datePicker = ScheduleDateSelection(selected: start, now: now(), calendar: calendar) }

    public func changeDay(_ day: Date) {
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: day)).day ?? 0
        guard let newStart = calendar.date(byAdding: .day, value: delta, to: start),
              let newEnd = calendar.date(byAdding: .day, value: delta, to: end) else { return }
        start = newStart
        end = newEnd
        if save() { datePicker = nil }
    }

    func changeTitle(_ value: String) {
        guard let selectedID, value != title else { return }
        do {
            try notes.update(noteID) { note in
                guard let i = note.schedules.firstIndex(where: { $0.id == selectedID && !$0.isDeleted }) else { return }
                note.schedules[i].title = value
                note.schedules[i].modified = now()
            }
            title = value
            reload()
            onSave?(noteID, selectedID, false)
        } catch { self.error = error.localizedDescription }
    }

    var showsImminentLead: Bool { selectedItem != nil && !dateOnly }

    var defaultLeadLabel: String {
        let minutes = Int(displayOptions.imminentLeadTime / 60)
        return "기본(" + (ImminentLead(rawValue: minutes)?.label ?? "\(minutes)분 전") + ")"
    }

    func chooseImminentLead(_ value: ImminentLead?) {
        guard showsImminentLead, let selectedID else { return }
        do {
            try notes.update(noteID) { note in
                guard let index = note.schedules.firstIndex(where: { $0.id == selectedID && !$0.isDeleted && !$0.isDateOnly }) else { return }
                // 로컬 표시만 바뀌므로 외부 충돌 판정에 쓰는 항목 수정 시각은 유지한다.
                note.schedules[index].imminentLeadMinutes = value
            }
            reload()
        } catch { self.error = error.localizedDescription }
    }

    public func chooseCalendar(_ id: String) {
        guard let selectedID else { return }
        do {
            try notes.update(noteID) { note in
                guard let i = note.schedules.firstIndex(where: { $0.id == selectedID && !$0.isDeleted }) else { return }
                note.schedules[i].pendingCalendarID = id
                note.schedules[i].modified = now()
            }
            reload()
            onSave?(noteID, selectedID, false)
        } catch { self.error = error.localizedDescription }
    }

    public var destination: (ScheduleItem) -> ScheduleDestination? = { _ in nil }
    public let calendar: Calendar
    public let now: () -> Date
    private var editingPrefix = ""
    private var metadataRevision = 0
    private var observation: StoreObservation?
    public var title = ""
    public var start = Date()
    public var end = Date()
    public var dateOnly = false
    public var hasEnd = false
    public var completed = false
    public private(set) var error: String?
    public var onSave: (@MainActor (NoteID, String, Bool) -> Void)?
    private let notes: any NoteStoring
    public init(noteID: NoteID, notes: any NoteStoring, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) throws {
        self.noteID = noteID; self.notes = notes; self.calendar = calendar; self.now = now
        let note = try notes.load(noteID)
        items = note.schedules.filter { !$0.isDeleted }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        select(note.displayedSchedule(at: now())?.id ?? items.first?.id)
        observation = notes.observe { [weak self] change in
            guard let self, change.id == self.noteID else { return }
            DispatchQueue.main.async { [weak self] in self?.reload() }
        }
    }
    public func select(_ id: String?) {
        focusToken += 1
        datePicker = nil
        selectedID = id
        let item = items.first { $0.id == id }
        title = item?.title ?? (try? notes.load(noteID).title) ?? ""
        start = item?.start ?? Date()
        end = item?.end ?? calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        if item?.isDateOnly == true, item?.end != nil {
            end = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        }
        dateOnly = item?.isDateOnly ?? false
        hasEnd = item?.end != nil
        completed = item?.isCompleted ?? false
        error = nil
        editingPrefix = item.map { $0.title.isEmpty ? "" : $0.title + " " } ?? ""
        input = item.map { ($0.title.isEmpty ? "" : $0.title + " ") + ReminderPresentation.editingExpression($0, calendar: calendar) } ?? ""
        candidateIndex = candidates.firstIndex(where: { $0.kind == item?.kind }) ?? 0
    }
    public func reload() {
        do {
            let previous = selectedItem
            items = try notes.load(noteID).schedules.filter { !$0.isDeleted }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            if let current = selectedItem, let previous {
                if current.title != previous.title { title = current.title }
                if current.start != previous.start { start = current.start }
                if current.isCompleted != previous.isCompleted { completed = current.isCompleted }
                if current.end != previous.end || current.isDateOnly != previous.isDateOnly {
                    dateOnly = current.isDateOnly
                    hasEnd = current.end != nil
                    if let finish = current.end {
                        end = dateOnly ? calendar.date(byAdding: .day, value: -1, to: finish) ?? finish : finish
                    } else { end = calendar.date(byAdding: .hour, value: 1, to: current.start) ?? current.start }
                }
            }
            metadataRevision += 1
        }
        catch { self.error = error.localizedDescription }
    }
    private func rebuildCandidates() {
        let previousKind = candidates.indices.contains(candidateIndex) ? candidates[candidateIndex].kind : nil
        candidates = []; expressionRanges = []; error = nil
        let parsingInput = !editingPrefix.isEmpty && input.hasPrefix(editingPrefix)
            ? String(repeating: " ", count: (editingPrefix as NSString).length) + String(input.dropFirst(editingPrefix.count)) : input
        guard let expression = DateTimeParser.firstExpression(in: parsingInput, now: now(), calendar: calendar) else { return }
        expressionRanges = expression.ranges
        let start = expression.isDateOnly ? calendar.startOfDay(for: expression.start) : expression.start
        if selectedID == nil && (expression.isDateOnly ? start < calendar.startOfDay(for: now()) : start < now()) { return }
        let source = NSMutableString(string: input)
        for range in expression.ranges.reversed() { source.deleteCharacters(in: range) }
        let title: String
        do { title = try candidateTitle(from: source as String) }
        catch { self.error = error.localizedDescription; return }
        let end = expression.end.map { expression.isDateOnly ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))! : $0 }
        let eventEnd = end ?? calendar.date(byAdding: expression.isDateOnly ? .day : .hour, value: 1, to: start)!
        candidates = [ScheduleItem(id: "candidate-event", start: start, end: eventEnd, isDateOnly: expression.isDateOnly, title: title)]
        if end == nil { candidates.append(ScheduleItem(id: "candidate-reminder", start: start, isDateOnly: expression.isDateOnly, title: title)) }
        candidateIndex = candidates.firstIndex(where: { $0.kind == previousKind }) ?? 0
    }
    private func candidateTitle(from inputTitle: String) throws -> String {
        let entered = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return entered }
        let note = try notes.load(noteID)
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let firstLine = note.body.components(separatedBy: .newlines).first ?? ""
        return NotePreviewText.firstLine(in: firstLine) ?? ""
    }
    public func moveCandidate(_ offset: Int) { candidateIndex = min(max(0, candidateIndex + offset), max(0, candidates.count - 1)) }
    @discardableResult public func submitCandidate() -> Bool {
        guard candidates.indices.contains(candidateIndex) else { return false }
        let item = candidates[candidateIndex]
        title = item.title; start = item.start; dateOnly = item.isDateOnly; hasEnd = item.end != nil
        end = item.end.map { dateOnly ? calendar.date(byAdding: .day, value: -1, to: $0)! : $0 } ?? item.start
        guard save() else { return false }
        reload(); select(nil); return true
    }
    public func toggleCompleted(_ id: String) {
        do {
            try notes.update(noteID) { note in
                guard let index = note.schedules.firstIndex(where: { $0.id == id && !$0.isDeleted && $0.kind == .reminder }) else { return }
                note.schedules[index].isCompleted.toggle()
                note.schedules[index].modified = now()
                if let todo = note.schedules[index].todo { note.body = todo.settingCompleted(note.schedules[index].isCompleted, in: note.body) }
            }
            reload()
            guard let item = items.first(where: { $0.id == id }), item.kind == .reminder else { return }
            if item.isCompleted { completedInList.insert(id) } else { completedInList.remove(id) }
            if selectedID == id { completed = item.isCompleted }
        } catch { self.error = error.localizedDescription }
    }
    public func presentation(_ item: ScheduleItem) -> ReminderPresentation {
        ReminderPresentation(item: item, now: now(), options: displayOptions, calendar: calendar)
    }
    public func destinationForItem(_ item: ScheduleItem) -> ScheduleDestination? {
        _ = metadataRevision
        return destination(item)
    }
    public func destinationForCandidate(_ item: ScheduleItem) -> ScheduleDestination? {
        var target = item
        if let existing = items.first(where: { $0.id == selectedID }), existing.kind == item.kind { target.link = existing.link }
        return destinationForItem(target)
    }
    @discardableResult public func save() -> Bool {
        let startValue = dateOnly ? calendar.startOfDay(for: start) : start
        let endValue = hasEnd ? (dateOnly ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))! : end) : nil
        if let endValue, endValue <= startValue { error = "종료는 시작보다 뒤여야 합니다"; return false }
        do {
            if let selectedID, !(try notes.load(noteID).schedules.contains { $0.id == selectedID && !$0.isDeleted }) {
                error = "예정이 삭제되었습니다"; return false
            }
            var savedID = ""
            var createsNewKind = false
            try notes.update(noteID) { note in
                let index = note.schedules.firstIndex { $0.id == selectedID && !$0.isDeleted }
                var item = index.map { note.schedules[$0] } ?? ScheduleItem(start: startValue)
                if item.kind != (hasEnd ? .event : .reminder) { item.pendingCalendarID = nil }
                item.title = title; item.start = startValue; item.end = endValue
                item.isDateOnly = dateOnly; item.isCompleted = hasEnd ? false : completed
                item.modified = Date()
                savedID = item.id
                createsNewKind = index == nil || index.map { note.schedules[$0].kind != item.kind } == true
                if let index {
                    if item.kind == .reminder, item.isCompleted != note.schedules[index].isCompleted,
                       let todo = item.todo { note.body = todo.settingCompleted(item.isCompleted, in: note.body) }
                    note.schedules[index] = item
                } else { note.schedules.append(item) }
            }
            reload()
            onSave?(noteID, savedID, createsNewKind)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult public func remove() -> Bool {
        guard let selectedID else { return false }
        do {
            try notes.update(noteID) { note in
                guard let index = note.schedules.firstIndex(where: { $0.id == selectedID }) else { return }
                note.schedules[index].markDeleted()
            }
            reload(); select(nil)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

