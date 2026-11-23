import Foundation

/// MCP 인자와 실행별 접수 파일에서 같은 검사를 사용한다.
package struct ProposalArguments: Codable, Sendable {
    package enum Kind: String, Codable, CaseIterable { case todos = "add_todos", reminder = "add_reminder", event = "add_event", newNote = "create_note" }
    package var kind: Kind
    package var note_id: String?
    package var lines: [String]?
    package var title: String?
    package var markdown: String?
    package var space_id: String?
    package var start: String?
    package var end: String?
    package var date_only: Bool?
    package var time_zone: String?

    package var fields: Set<String> {
        switch kind {
        case .todos: ["kind", "note_id", "lines"]
        case .reminder: ["kind", "note_id", "title", "start", "date_only", "time_zone"]
        case .event: ["kind", "note_id", "title", "start", "end", "date_only", "time_zone"]
        case .newNote: ["kind", "note_id", "title", "markdown", "space_id"]
        }
    }

    private func identifier(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 255 && !s.hasPrefix(".") && !s.contains("/") && TodoSubmission.valid(lines: [s])
    }

    package func content() throws -> AgentProposal.Content {
        guard note_id.map(identifier) != false, kind == .newNote || note_id != nil else { throw Invalid.target }
        if kind == .todos {
            guard let lines, TodoSubmission.valid(lines: lines) else { throw Invalid.lines }
            return .todos(lines)
        }
        guard let title, TodoSubmission.valid(lines: [title]) else { throw Invalid.title }
        if kind == .newNote {
            guard let markdown, markdown.utf8.count <= 32 * 1024, !markdown.utf8.contains(0),
                  space_id.map(identifier) != false else { throw Invalid.note }
            return .newNote(title: title, markdown: markdown)
        }
        guard let date_only, let time_zone, time_zone.utf8.count <= 128,
              let zone = TimeZone(identifier: time_zone), let start else { throw Invalid.date }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = zone
        format.dateFormat = date_only ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ss"
        format.isLenient = false
        func read(_ value: String) throws -> Date {
            guard value.utf8.count == (date_only ? 10 : 19), let d = format.date(from: value),
                  format.string(from: d) == value else { throw Invalid.date }
            return d
        }
        let first = try read(start), last = try end.map(read)
        guard (kind == .event) == (last != nil), last.map({ $0 > first }) != false else { throw Invalid.range }
        return .schedule(kind: kind == .event ? .event : .reminder, start: first, end: last,
                         dateOnly: date_only, timeZone: time_zone, title: title)
    }

    package enum Invalid: String, LocalizedError {
        case target = "대상 노트 ID를 확인해 주세요."
        case title = "제목은 비어 있지 않은 한 줄로 1024바이트까지 쓸 수 있습니다."
        case lines = "할 일은 한 줄에 1024바이트까지, 1개에서 32개까지 제안할 수 있습니다."
        case note = "새 노트 본문은 32KiB까지이며 올바른 스페이스 ID가 필요합니다."
        case date = "현지 날짜, 시각과 시간대를 확인해 주세요."
        case range = "일정의 끝은 시작보다 늦어야 합니다."
        package var errorDescription: String? { rawValue }
    }
}

package struct ProposalSubmission: Codable, Sendable {
    package let arguments: ProposalArguments
    package let version: String?
    package init(arguments: ProposalArguments, version: String?) {
        self.arguments = arguments
        self.version = version
    }
}
