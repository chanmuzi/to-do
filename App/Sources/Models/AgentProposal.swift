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
        package var removedTail: Data?
        package var addedTail: Data?

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
    package var lines: [String] {
        if case .todos(let lines) = content { lines } else { [] }
    }
    package static func submitted(_ input: TodoSubmission, key: String, request: AgentRequest, source: NoteID?) -> Self {
        Self(id: UUID(), requestID: request.id, runID: request.runID, toolCallID: key,
             target: .note(NoteID(rawValue: input.noteID)), sourceNoteID: source, title: "할 일 \(input.lines.count)개 추가",
             content: .todos(input.lines), baseVersion: input.version, createdAt: Date(), status: .pending)
    }
}
