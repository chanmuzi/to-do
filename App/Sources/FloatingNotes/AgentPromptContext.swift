import Foundation
import Library
import Models

struct AgentPromptContext: Encodable {
    let kind: String
    let name: String
    var notes: [String]
    var omitted: Int

    static func resolve(_ items: [AgentContextItem], index: LibraryIndex, spaces: [Space]) -> [Self] {
        let byID = Dictionary(uniqueKeysWithValues: index.notes.map { ($0.id, $0) })
        let bySpace = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        let limit = 50
        return items.map { item in
            let matches: [Note]
            let kind: String
            switch item {
            case .note(let id):
                kind = "note"
                matches = byID[id].map { [$0] } ?? []
            case .space(let id):
                kind = "space"
                matches = bySpace[id] == nil ? [] : index.rows(for: .space(id))
            case .view(let view):
                kind = "view"
                matches = index.rows(for: view == .today ? .today : .floating)
            case .period(let period):
                kind = "period"
                let span = period.interval(at: index.now, calendar: index.calendar)
                matches = index.notes.filter { note in
                    guard let span else { return false }
                    return (span.start..<span.end).contains(note.created) || (span.start..<span.end).contains(note.modified)
                }.sorted {
                    if $0.modified == $1.modified { return $0.id.rawValue < $1.id.rawValue }
                    return $0.modified > $1.modified
                }
            }
            return Self(kind: kind, name: item.name(notes: byID, spaces: bySpace),
                        notes: matches.prefix(limit).map { $0.id.rawValue + ".md" },
                        omitted: max(0, matches.count - limit))
        }
    }
}
