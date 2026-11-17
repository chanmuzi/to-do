import Foundation
import Models

/// 로컬 달력의 날짜로 분류한다. 아카이브는 파일을 옮기지 않는 가상 보기다.
public struct LibraryIndex: Sendable {
    public let notes: [Note]
    public let trash: [Note]
    public let windows: [NoteID: NoteWindowState]
    public let now: Date
    public let calendar: Calendar

    public init(notes: [Note], trash: [Note] = [], windows: [NoteID: NoteWindowState] = [:],
                now: Date = Date(), calendar: Calendar = .current) {
        self.notes = notes; self.trash = trash; self.windows = windows
        self.now = now; self.calendar = calendar
    }

    public func isArchived(_ note: Note) -> Bool {
        let day = calendar.startOfDay(for: note.created)
        guard let boundary = calendar.date(byAdding: .day, value: 7, to: day) else { return false }
        return boundary <= calendar.startOfDay(for: now)
    }

    public func month(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public var archiveMonths: [String] {
        Array(Set(notes.filter(isArchived).map { month(of: $0.created) })).sorted(by: >)
    }
    public var upcoming: [Note] {
        notes.filter { ($0.reminder ?? .distantPast) >= now }
            .sorted { $0.reminder! < $1.reminder! }
    }
    public func days(in space: SpaceID?) -> [Date] {
        Array(Set(notes.filter { $0.spaceID == space && !isArchived($0) }
            .map { calendar.startOfDay(for: $0.created) })).sorted(by: >)
    }
    public func rows(for selection: LibrarySelection, query: String = "") -> [Note] {
        let source = selection == .trash ? trash : notes
        return source.filter { note in
            let included: Bool
            switch selection {
            case .today:
                included = calendar.isDate(note.created, inSameDayAs: now)
                    || note.reminder.map { calendar.isDate($0, inSameDayAs: now) } == true
            case .floating: included = windows[note.id]?.isOpen == true
            case .all, .trash: included = true
            case .reminders: included = note.reminder != nil
            case .space(let id): included = note.spaceID == id && !isArchived(note)
            case .day(let id, let day):
                included = note.spaceID == id && !isArchived(note) && calendar.isDate(note.created, inSameDayAs: day)
            case .archive(let month): included = isArchived(note) && self.month(of: note.created) == month
            }
            return included && (query.isEmpty || (note.title + "\n" + note.body)
                .localizedStandardContains(query))
        }.sorted {
            if selection == .floating {
                let a = windows[$0.id]?.stackOrder ?? 0, b = windows[$1.id]?.stackOrder ?? 0
                if a != b { return a > b }
            }
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.id.rawValue < $1.id.rawValue
        }
    }
}
