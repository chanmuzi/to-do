import Foundation
import Models

/// 편집기 의존 없이 목록용 텍스트와 투두 개수만 추린다. 코드 울타리 안 체크박스는 세지 않는다.
enum LibraryPreview {
    static func lines(_ body: String) -> [String] {
        body.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"^\s*(?:[-*] )?(?:\[[ xX]\] |#{1,3} |[>+] )?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
    }
    static func isEmpty(_ note: Note) -> Bool { note.title.isEmpty && lines(note.body).allSatisfy(\.isEmpty) }
    static func title(_ note: Note) -> String {
        if !note.title.isEmpty { return note.title }
        return lines(note.body).first(where: { !$0.isEmpty }) ?? "제목 없음"
    }
    static func subtitle(_ note: Note) -> String {
        let values = lines(note.body)
        let first = values.firstIndex(where: { !$0.isEmpty })
        let visible = note.title.isEmpty ? (first.map { Array(values.dropFirst($0 + 1)) } ?? []) : values
        let text = visible.filter { !$0.isEmpty }.joined(separator: ", ")
        if !text.isEmpty { return text }
        if first != nil { return "" }
        let parts = progress(note.body).split(separator: "/").compactMap { Int($0) }
        let remaining = parts.count == 2 ? parts[1] - parts[0] : 0
        return remaining > 0 ? "투두 \(remaining)개 남음" : ""
    }
    static func upcomingTitle(_ note: Note, now: Date, calendar: Calendar) -> String {
        let item = note.displayedSchedule(at: now, calendar: calendar)
        if let title = item?.title, !title.isEmpty { return title }
        if !isEmpty(note) { return title(note) }
        return item?.kind == .event ? "일정" : "리마인더"
    }

    static func text(_ body: String) -> String {
        body.split(separator: "\n").prefix(3).map {
            String($0).replacingOccurrences(of: #"^\s*(?:[-*] )?(?:\[[ xX]\] |#{1,3} |[>+] )?"#, with: "", options: .regularExpression)
        }.joined(separator: ", ")
    }
    static func progress(_ body: String) -> String {
        var fence: String?, done = 0, total = 0
        for line in body.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("```") || text.hasPrefix("~~~") {
                let marker = String(text.prefix(3)); if fence == marker { fence = nil } else if fence == nil { fence = marker }; continue
            }
            guard fence == nil else { continue }
            let value = text.hasPrefix("- ") ? String(text.dropFirst(2)) : text
            if ["[ ]", "[x]", "[X]"].contains(value) || value.hasPrefix("[ ] ") || value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
                total += 1; if !value.hasPrefix("[ ]") { done += 1 }
            }
        }
        return total == 0 ? "" : "\(done)/\(total)"
    }
}
