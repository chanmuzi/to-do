import Foundation
import Models

/// 로컬 달력의 날짜로 분류한다. 아카이브는 파일을 옮기지 않는 가상 보기다.
public struct LibraryIndex: Sendable {
    public let notes: [Note]
    public let trash: [Note]
    public let windows: [NoteID: NoteWindowState]
    public let events: [CalendarEvent]
    public let now: Date
    public let calendar: Calendar

    public init(notes: [Note], trash: [Note] = [], windows: [NoteID: NoteWindowState] = [:],
                events: [CalendarEvent] = [], now: Date = Date(), calendar: Calendar = .current) {
        self.notes = notes; self.trash = trash; self.windows = windows
        self.events = events; self.now = now; self.calendar = calendar
    }

    public func month(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public var archiveMonths: [String] {
        Array(Set(notes.filter(\.isArchived).map { month(of: $0.created) })).sorted(by: >)
    }
    public static func upcomingInterval(now: Date, calendar: Calendar) -> DateInterval {
        DateInterval(start: now, end: calendar.date(byAdding: .day, value: 7, to: now) ?? now)
    }

    public var upcoming: [UpcomingRow] {
        let interval = Self.upcomingInterval(now: now, calendar: calendar)
        func included(_ item: ScheduleItem) -> Bool {
            guard !item.isDeleted, !item.isCompleted, item.start < interval.end else { return false }
            if let end = item.end { return end > now }
            return item.isUpcoming(at: now, calendar: calendar)
        }
        var rows: [UpcomingRow] = []
        var linked: [ScheduleItem] = []
        for note in notes {
            for item in note.schedules {
                if item.kind == .event, let link = item.link, link.kind != .reminder { linked.append(item) }
                if !note.isArchived && included(item) { rows.append(.note(note, item)) }
            }
        }
        // 다른 캘린더에 복사한 일정은 같은 외부 ID를 가질 수 있다.
        func sameLocalItem(_ a: ScheduleItem.Link, _ b: ScheduleItem.Link) -> Bool {
            a.localID == b.localID && (a.externalID == nil || b.externalID == nil || a.externalID == b.externalID)
        }
        let links = events.compactMap { $0.item.link }
        let externalIDs = Dictionary(grouping: links, by: \.externalID)
            .mapValues { Set($0.map(\.localID)) }
        for event in events where event.item.kind == .event && included(event.item) {
            let duplicate = linked.contains { item in
                guard let a = item.link, let b = event.item.link,
                      !event.recurring || item.start == event.item.start else { return false }
                if sameLocalItem(a, b) { return true }
                guard let external = a.externalID, !links.contains(where: { sameLocalItem(a, $0) }) else { return false }
                return external == b.externalID && externalIDs[external]?.count == 1
            }
            if !duplicate { rows.append(.calendar(event)) }
        }
        var result: [UpcomingRow] = []
        for row in rows.sorted(by: { ($0.item.start, $0.id) < ($1.item.start, $1.id) }) {
            let duplicate = result.contains { other in
                if row.id == other.id { return true }
                guard row.item.kind == .event, row.item.start == other.item.start,
                      let a = row.item.link, let b = other.item.link else { return false }
                return sameLocalItem(a, b)
            }
            if !duplicate { result.append(row) }
        }
        return result
    }
    public func days(in space: SpaceID?) -> [Date] {
        Array(Set(notes.filter { $0.spaceID == space && !$0.isArchived }
            .map { calendar.startOfDay(for: $0.created) })).sorted(by: >)
    }
    enum SectionHeader: Hashable {
        case pinned, today, date(String)

        var title: String {
            switch self {
            case .pinned: "고정됨"
            case .today: "오늘"
            case .date(let title): title
            }
        }

        var symbol: String {
            switch self {
            case .pinned: "pin"
            case .today: "sun.max"
            case .date: "calendar"
            }
        }
    }

    struct Section: Identifiable {
        let header: SectionHeader?
        var id: SectionHeader? { header }
        var notes: [Note]
    }

    func sections(for selection: LibrarySelection) -> [Section] {
        let rows = rows(for: selection)
        guard !rows.isEmpty else { return [] }
        if selection == .today || selection == .floating {
            return [Section(header: nil, notes: rows)]
        }
        let groupsPinned: Bool = switch selection {
        case .archived, .archive, .trash: false
        default: true
        }
        var groups: [Section] = []
        var pinned: [Note] = []
        for note in rows {
            if groupsPinned && windows[note.id]?.isPinned == true {
                pinned.append(note)
                continue
            }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: note.modified),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            let header: SectionHeader = switch days {
            case ...0: .today
            case 1: .date("어제")
            case 2...7: .date("이전 7일")
            case 8...30: .date("이전 30일")
            default: .date("\(calendar.component(.year, from: note.modified))년 \(calendar.component(.month, from: note.modified))월")
            }
            if groups.last?.header == header { groups[groups.count - 1].notes.append(note) }
            else { groups.append(Section(header: header, notes: [note])) }
        }
        if !pinned.isEmpty { groups.insert(Section(header: .pinned, notes: pinned), at: 0) }
        return groups
    }

    public func rows(for selection: LibrarySelection) -> [Note] {
        let source = selection == .trash ? trash : notes
        return source.filter { note in
            if note.isArchived {
                switch selection { case .trash, .archived, .archive: break; default: return false }
            }
            let included: Bool
            switch selection {
            case .today:
                included = calendar.isDate(note.created, inSameDayAs: now)
                    || note.schedules.contains { !$0.isDeleted && !$0.isCompleted && calendar.isDate($0.start, inSameDayAs: now) }
            case .floating: included = windows[note.id]?.isPinned == true
            case .archived: included = note.isArchived
            case .all, .trash: included = true
            case .reminders: included = note.schedules.contains { !$0.isDeleted && !$0.isCompleted }
            case .space(let id): included = note.spaceID == id && !note.isArchived
            case .day(let id, let day):
                included = note.spaceID == id && !note.isArchived && calendar.isDate(note.created, inSameDayAs: day)
            case .archive(let month): included = note.isArchived && self.month(of: note.created) == month
            }
            return included
        }.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.id.rawValue < $1.id.rawValue
        }
    }
}

public enum UpcomingRow: Identifiable, Sendable {
    case note(Note, ScheduleItem)
    case calendar(CalendarEvent)

    public var item: ScheduleItem {
        switch self { case .note(_, let item): item; case .calendar(let event): event.item }
    }
    public var id: String {
        switch self {
        case .note(let note, let item): "note/\(note.id.rawValue)/\(item.id)"
        case .calendar(let event): "calendar/\(event.item.id)/\(event.item.start.timeIntervalSinceReferenceDate)"
        }
    }
}
