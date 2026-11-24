import Foundation
import Models

package struct TodayScheduleContext: Encodable {
    package struct Entry: Encodable {
        let title: String
        let start: String
        let end: String?
        let allDay: Bool
        let noteFile: String?
        let source: String
        let distance: TimeInterval
        enum CodingKeys: String, CodingKey { case title, start, end, allDay, noteFile, source }
    }

    package struct Section: Encodable {
        let status: String
        var items: [Entry]
        var omitted: Int

        init(_ entries: [Entry]? = nil) {
            let sorted = (entries ?? []).sorted {
                ($0.distance, $0.start, $0.title, $0.noteFile ?? "", $0.end ?? "") <
                ($1.distance, $1.start, $1.title, $1.noteFile ?? "", $1.end ?? "")
            }
            status = entries == nil ? "알 수 없음" : sorted.isEmpty ? "없음" : "있음"
            items = Array(sorted.prefix(20))
            omitted = sorted.count - items.count
        }

        mutating func omitLast() {
            items.removeLast()
            omitted += 1
        }
    }

    package var events = Section()
    package var reminders = Section()
    package init() {}

    package mutating func omitFarthest() -> Bool {
        if let last = events.items.last, last.distance >= (reminders.items.last?.distance ?? -1) {
            events.omitLast()
        } else if !reminders.items.isEmpty {
            reminders.omitLast()
        } else { return false }
        return true
    }

    static func section(kind: ScheduleItem.Kind, selection: (calendarID: String, items: [CalendarEvent])?,
                        notes: [Note], day: DateInterval, now: Date, calendar: Calendar) -> Section {
        guard let selection else { return Section() }
        let iso = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: calendar.timeZone)
        func entry(_ item: ScheduleItem, owner: Note?) -> Entry {
            let distance = item.end.map { max(0, item.start.timeIntervalSince(now), now.timeIntervalSince($0)) }
                ?? abs(item.start.timeIntervalSince(now))
            let title = item.title.isEmpty ? owner?.title ?? "" : item.title
            return Entry(title: title, start: item.start.formatted(iso), end: item.end?.formatted(iso),
                         allDay: item.isDateOnly, noteFile: owner.map { $0.id.rawValue + ".md" },
                         source: owner == nil ? "외부 캘린더" : "Float 노트", distance: distance)
        }
        let local = notes.flatMap { note in note.schedules.filter { $0.kind == kind }.map { (note, $0) } }
        var entries = local.compactMap { note, item -> Entry? in
            guard item.link == nil, !item.isDeleted, !item.isCompleted, !note.isArchived,
                  item.pendingCalendarID == nil || item.pendingCalendarID == selection.calendarID,
                  item.start < day.end, item.end.map({ $0 > day.start }) ?? true else { return nil }
            return entry(item, owner: note)
        }
        let linked = local.filter { _, item in item.link != nil && (item.link?.kind == nil || item.link?.kind == kind) }
        let byLocal = Dictionary(grouping: linked, by: { $0.1.link?.localID })
        let byExternal = Dictionary(grouping: linked, by: { $0.1.link?.externalID })
        let remoteIDs = Dictionary(grouping: selection.items.compactMap { $0.item.link }, by: \.externalID)
            .mapValues { Set($0.map(\.localID)) }
        for row in selection.items {
            var owner: (Note, ScheduleItem)?
            if let link = row.item.link {
                func sameOccurrence(_ candidate: (Note, ScheduleItem)) -> Bool {
                    !row.recurring || candidate.1.start == row.item.start
                }
                let exact = (byLocal[link.localID] ?? []).filter {
                    let external = $0.1.link?.externalID
                    return sameOccurrence($0) && (external == nil || link.externalID == nil || external == link.externalID)
                }
                if exact.count == 1 { owner = exact.first }
                else if exact.isEmpty, let external = link.externalID, remoteIDs[external]?.count == 1 {
                    let candidates = (byExternal[external] ?? []).filter(sameOccurrence)
                    if candidates.count == 1 { owner = candidates.first }
                }
            }
            if let (_, item) = owner, item.isDeleted || item.isCompleted { continue }
            entries.append(entry(row.item, owner: owner?.0))
        }
        return Section(entries)
    }
}
