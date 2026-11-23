import Foundation
import Models

package extension NoteStoring {
    func writeSchedule(_ item: ScheduleItem, in id: NoteID) throws {
        try update(id) { note in
            if let index = note.schedules.firstIndex(where: { $0.id == item.id }) { note.schedules[index] = item }
            else { note.schedules.append(item) }
        }
    }

    func removeSchedule(_ itemID: String, in id: NoteID) throws {
        try update(id) { note in
            guard let index = note.schedules.firstIndex(where: { $0.id == itemID }) else { return }
            if note.schedules[index].link == nil { note.schedules.remove(at: index) }
            else { note.schedules[index].isDeleted = true; note.schedules[index].modified = Date() }
        }
    }
}
