import Foundation

public struct AgentProposal: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, CaseIterable, Codable, Sendable { case pending, accepted, undone, discarded }
    public enum Target: Codable, Equatable, Sendable {
        case note(NoteID), newNote(NoteID, SpaceID?), instructions
    }
    public enum Content: Codable, Equatable, Sendable {
        case todos([String])
        case schedule(kind: ScheduleItem.Kind, start: Date, end: Date?, dateOnly: Bool, timeZone: String, title: String)
        case newNote(title: String, markdown: String)
        case instructions(before: String, after: String)
    }
    public struct Receipt: Codable, Equatable, Sendable {
        public var operationID: UUID
        public var appliedAt: Date
        public var previousFingerprint: String
        public var appliedFingerprint: String
        package struct BodyUndo: Codable, Equatable, Sendable {
            package var applied: String
            package var added: Data
            package var removed: Data
            package init(before: Data, after: Data) {
                let prefix = zip(before, after).prefix(while: { $0 == $1 }).count
                applied = TodoSubmission.fingerprint(after)
                added = Data(after.dropFirst(prefix))
                removed = Data(before.dropFirst(prefix))
            }
        }
        package var bodyUndo: BodyUndo?
        package var removedTail: Data?
        package var addedTail: Data?

        package init(previousFingerprint: String, appliedFingerprint: String) {
            operationID = UUID()
            appliedAt = Date()
            self.previousFingerprint = previousFingerprint
            self.appliedFingerprint = appliedFingerprint
        }

        package init(before: Data, after: Data) {
            operationID = UUID()
            appliedAt = Date()
            previousFingerprint = TodoSubmission.fingerprint(before)
            appliedFingerprint = TodoSubmission.fingerprint(after)
            let prefix = zip(before, after).prefix(while: { $0 == $1 }).count
            removedTail = Data(before.dropFirst(prefix))
            addedTail = Data(after.dropFirst(prefix))
        }
    }

    public var id: UUID
    public var requestID: UUID
    public var runID: UUID
    public var toolCallID: String
    public var target: Target
    public var sourceNoteID: NoteID?
    public var title: String
    public var content: Content
    public var baseVersion: String?
    public var createdAt: Date
    public var seenAt: Date?
    public var status: Status
    public var receipt: Receipt?
    package enum Operation: String, Codable, Sendable { case accept, undo }
    package var operation: Operation?
    package var requiresReview: Bool?
    package var targetID: NoteID? {
        if case .note(let id) = target { id } else { nil }
    }
    package var createdNoteID: NoteID? {
        if case .newNote(let id, _) = target { id } else { nil }
    }
    package var cardNoteID: NoteID? { createdNoteID == nil ? targetID : sourceNoteID }
    package var scheduleItem: ScheduleItem? {
        guard case let .schedule(_, start, end, dateOnly, zoneID, title) = content else { return nil }
        // 날짜만 있는 항목은 Store가 사용하는 현지 달력의 같은 날짜로 옮긴다.
        func localDay(_ date: Date) -> Date {
            guard dateOnly, let zone = TimeZone(identifier: zoneID) else { return date }
            var source = Calendar(identifier: .gregorian)
            source.timeZone = zone
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            return local.date(from: source.dateComponents([.year, .month, .day], from: date)) ?? date
        }
        return ScheduleItem(id: id.uuidString, start: localDay(start), end: end.map(localDay), isDateOnly: dateOnly,
                            title: title, modified: createdAt)
    }
    package var lines: [String] {
        if case .todos(let lines) = content { lines } else { [] }
    }
    package static func submitted(_ entry: ProposalSubmission, key: String, request: AgentRequest,
                                  source: NoteID?, reservedID: NoteID) throws -> Self {
        let args = entry.arguments
        let content = try args.content()
        let note = args.note_id.map(NoteID.init(rawValue:))
        let target: AgentProposal.Target
        let title: String
        switch content {
        case .newNote(let name, _):
            target = .newNote(reservedID, args.space_id.map(SpaceID.init(rawValue:)))
            title = "새 노트: " + name
        case .instructions: throw CocoaError(.fileReadCorruptFile)
        default:
            guard let note, entry.version != nil else { throw CocoaError(.fileReadCorruptFile) }
            target = .note(note)
            if case .todos(let lines) = content { title = "할 일 \(lines.count)개 추가" }
            else { title = args.kind == .event ? "일정 추가" : "리마인더 추가" }
        }
        return AgentProposal(id: UUID(), requestID: request.id, runID: request.runID, toolCallID: key,
                             target: target, sourceNoteID: args.kind == .newNote ? note ?? source : source,
                             title: title, content: content, baseVersion: entry.version, createdAt: Date(), status: .pending)
    }
    package static func submitted(_ input: TodoSubmission, key: String, request: AgentRequest, source: NoteID?) -> Self {
        Self(id: UUID(), requestID: request.id, runID: request.runID, toolCallID: key,
             target: .note(NoteID(rawValue: input.noteID)), sourceNoteID: source, title: "할 일 \(input.lines.count)개 추가",
             content: .todos(input.lines), baseVersion: input.version, createdAt: Date(), status: .pending)
    }
}
