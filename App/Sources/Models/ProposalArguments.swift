import Foundation

/// MCP 인자와 실행별 접수 파일에서 같은 검사를 사용한다.
package struct ProposalArguments: Codable, Sendable {
    package enum Kind: String, Codable, CaseIterable { case todos = "add_todos", reminder = "add_reminder", event = "add_event", newNote = "create_note", instructions = "change_instructions" }
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

    package var user_message: String?
    package var before: String?
    package var after: String?

    package var fields: Set<String> {
        switch kind {
        case .instructions: ["kind", "user_message", "before", "after"]
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
        if kind == .instructions {
            guard let user_message, !user_message.isEmpty else { throw Invalid.missingMessage }
            guard note_id == nil, let before, let after else { throw Invalid.instructionFields }
            guard [before, after, user_message].allSatisfy({ $0.utf8.count <= 96 * 1024 && !$0.utf8.contains(0) })
            else { throw Invalid.instructionText }
            guard !before.utf8.elementsEqual(after.utf8) else { throw Invalid.unchangedInstructions }
            return .instructions(before: before, after: after)
        }
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
        case missingMessage = "user_message에 이번 실행의 사용자 메시지 원문 전체를 넣어 주세요."
        case evidence = "user_message가 이번 실행의 사용자 메시지 원문과 일치하지 않습니다."
        case instructionBase = "before가 이번 실행을 시작할 때의 지침 원문과 일치하지 않습니다."
        case instructionFields = "지침 변경에는 대상 노트 없이 before와 after에 문서 전체를 넣어 주세요."
        case instructionText = "user_message, before, after는 각각 UTF-8 96KiB 이하이고 널 문자를 포함할 수 없습니다."
        case unchangedInstructions = "before와 after의 지침 내용이 같습니다."
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
