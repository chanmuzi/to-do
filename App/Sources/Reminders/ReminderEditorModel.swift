import AppKit
import SwiftUI
import Observation
import Models
import Store
import Theme

@MainActor @Observable
public final class ReminderEditorModel {
    public let noteID: NoteID
    public private(set) var items: [ScheduleItem] = []
    public var selectedID: String?
    public var title = ""
    public var start = Date()
    public var end = Date()
    public var dateOnly = false
    public var hasEnd = false
    public var completed = false
    public private(set) var error: String?
    public var onSave: (@MainActor (NoteID, String, Bool) -> Void)?
    private let notes: any NoteStoring
    public init(noteID: NoteID, notes: any NoteStoring) throws {
        self.noteID = noteID; self.notes = notes
        let note = try notes.load(noteID)
        items = note.schedules.filter { !$0.isDeleted }
        select(note.displayedSchedule(at: Date())?.id ?? items.first?.id)
    }
    public func select(_ id: String?) {
        selectedID = id
        let item = items.first { $0.id == id }
        title = item?.title ?? (try? notes.load(noteID).title) ?? ""
        start = item?.start ?? Date()
        end = item?.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        if item?.isDateOnly == true, item?.end != nil {
            end = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        }
        dateOnly = item?.isDateOnly ?? false
        hasEnd = item?.end != nil
        completed = item?.isCompleted ?? false
        error = nil
    }
    @discardableResult public func save() -> Bool {
        let startValue = dateOnly ? Calendar.current.startOfDay(for: start) : start
        let endValue = hasEnd ? (dateOnly ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))! : end) : nil
        if let endValue, endValue <= startValue { error = "종료는 시작보다 뒤여야 합니다"; return false }
        do {
            var savedID = ""
            var createsNewKind = false
            try notes.update(noteID) { note in
                let index = note.schedules.firstIndex { $0.id == selectedID }
                var item = index.map { note.schedules[$0] } ?? ScheduleItem(start: startValue)
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
            onSave?(noteID, savedID, createsNewKind)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult public func remove() -> Bool {
        guard let selectedID else { return false }
        do {
            try notes.update(noteID) { note in
                guard let index = note.schedules.firstIndex(where: { $0.id == selectedID }) else { return }
                note.schedules[index].isDeleted = true
                note.schedules[index].modified = Date()
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

