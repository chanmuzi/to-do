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
}
