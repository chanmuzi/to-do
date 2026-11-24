import Foundation
import MarkdownSyntax
import Models
import Store

struct NoteCatalog {
    let directory: NoteDirectory
    let context: AgentNoteContext?
    let timeZone = TimeZone.current
    let now = Date()

    private func json(_ object: Object) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private func record(_ name: String) throws -> (metadata: Object, raw: String) {
        let file = try directory.file(name)
        let id = NoteID(rawValue: String(name.dropLast(3)))
        let note = NoteFileCodec.note(file.text, id: id, creation: file.created, modified: file.modified,
                                      archiveCutoff: context?.archiveCutoff ?? .distantPast)
        let iso = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true, timeZone: timeZone)
        let document = MarkdownDocument(note.body)
        let tasks = document.lines.compactMap(document.todoCompletion)
        func nearest(_ kind: ScheduleItem.Kind) -> Any {
            let active = note.schedules.filter { $0.kind == kind && !$0.isDeleted && !$0.isCompleted }
            guard let item = active.min(by: { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) })
            else { return NSNull() }
            return ["start": item.start.formatted(iso), "date_only": item.isDateOnly] as Object
        }
        let window = context?.windows[id.rawValue]
        let metadata: Object = [
            "name": name, "title": note.title, "created": note.created.formatted(iso),
            "modified": note.modified.formatted(iso), "time_zone": timeZone.identifier,
            "space": note.spaceID.flatMap { context?.spaces[$0.rawValue] } as Any,
            "archived": note.isArchived, "pinned": context.map { _ in window?.pinned ?? true } as Any,
            "open": context.map { _ in window?.open ?? false } as Any, "todo_remaining": tasks.filter { !$0 }.count,
            "todo_total": tasks.count, "nearest_reminder": nearest(.reminder), "nearest_event": nearest(.event),
            "body_characters": note.body.count
        ]
        return (metadata, file.text)
    }

    func list(_ arguments: Object) throws -> String {
        func integer(_ key: String, default fallback: Int) throws -> Int {
            guard let value = arguments[key] else { return fallback }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let result = Int(exactly: number) else { throw IntakeFailure("정수 인자가 필요합니다.") }
            return result
        }
        let limit = try integer("limit", default: 50)
        let offset = try integer("offset", default: 0)
        guard (1...200).contains(limit), offset >= 0, Set(arguments.keys).isSubset(of: ["limit", "offset", "since"])
        else { throw IntakeFailure("limit, offset, since 값을 확인해 주세요.") }
        var since = Date.distantPast
        if let value = arguments["since"] {
            guard let text = value as? String, let date = try? Date(text, strategy: .iso8601)
            else { throw IntakeFailure("since에 시간대를 포함한 ISO 8601 시각이 필요합니다.") }
            since = date
        }
        let entries = try directory.entries().filter { $0.modified >= since }.sorted {
            $0.modified == $1.modified ? $0.name < $1.name : $0.modified > $1.modified
        }
        let page = entries.dropFirst(offset).prefix(limit)
        var records: [Object] = []
        var unreadable: [String] = []
        for entry in page {
            do { records.append(try record(entry.name).metadata) }
            catch { unreadable.append(entry.name) }
        }
        let next = page.endIndex < entries.count ? page.endIndex : nil
        return try json(["notes": records, "unreadable": unreadable, "next_offset": next as Any])
    }

    func read(_ name: String) throws -> String {
        let item = try record(name)
        return try json(item.metadata) + "\n\n[원문]\n" + item.raw
    }
}
