import Foundation
import Models
import MarkdownSyntax

/// 한 번 파싱한 본문에서 제목 대체 글, 보조 줄과 빈 투두 요약을 함께 만든다.
struct LibraryPreview {
    let title: String
    let subtitle: String
    let isEmpty: Bool
    let completed: Int
    let total: Int

    init(_ note: Note) {
        self.init(title: note.title, markdown: note.body)
    }

    init(title noteTitle: String, markdown: String) {
        let document = MarkdownDocument(markdown)
        var visible: [String] = []
        var checked = 0, todos = 0
        for line in document.lines where line.kind != .fenceOpen && line.kind != .fenceClose {
            if case .todo(let done) = line.kind {
                todos += 1
                if done { checked += 1 }
            }
            var start = line.contentStart
            var text = ""
            for marker in line.markers {
                text += document.string(in: NSRange(location: start, length: marker.range.location - start))
                start = NSMaxRange(marker.range)
            }
            text += document.string(in: NSRange(location: start, length: line.end - start))
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { visible.append(trimmed) }
        }
        completed = checked
        total = todos
        isEmpty = noteTitle.isEmpty && visible.isEmpty
        title = noteTitle.isEmpty ? visible.first ?? "제목 없음" : noteTitle
        if visible.isEmpty && todos > checked {
            subtitle = "투두 \(todos - checked)개 남음"
        } else {
            subtitle = NotePreviewText.join(visible.dropFirst(noteTitle.isEmpty ? 1 : 0))
        }
    }

    func upcomingTitle(for item: ScheduleItem) -> String {
        if !item.title.isEmpty { return item.title }
        if !isEmpty { return title }
        return item.kind == .event ? "일정" : "리마인더"
    }
}
