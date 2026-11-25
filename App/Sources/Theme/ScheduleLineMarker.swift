import Foundation
import Models
import MarkdownSyntax

/// 같은 본문 줄의 활성 예정은 가장 이른 항목의 모습으로 한 번만 표시한다.
package struct ScheduleLineMarker: Equatable {
    package let text: String
    package let selectedID: String?
    package let isImminent: Bool
    package let label: String

    package static func markers(in note: Note, now: Date, options: NoteDisplayOptions,
                                calendar: Calendar) -> [Int: Self] {
        let active = note.schedules.filter { !$0.isDeleted && !$0.isCompleted && $0.inlineSource?.line != nil }
        guard !active.isEmpty else { return [:] }
        let document = MarkdownDocument(note.body)
        let valid = active.filter {
            guard let source = $0.inlineSource, let line = source.line, document.lines.indices.contains(line) else { return false }
            return document.lines[line].continuationOf == nil && document.blockSource(at: line) == source.text
        }
        var timeOptions = options
        timeOptions.reminder = .time
        return Dictionary(grouping: valid, by: { $0.inlineSource!.line! }).mapValues { group in
            let first = group.min { ($0.start, $0.id) < ($1.start, $1.id) }!
            let display = ReminderPresentation(item: first, now: now, options: timeOptions, calendar: calendar)
            return Self(text: first.inlineSource!.text, selectedID: group.count == 1 ? first.id : nil,
                        isImminent: display.status == .imminent, label: display.accessibilityLabel(title: first.title))
        }
    }
}
