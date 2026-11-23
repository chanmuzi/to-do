import Foundation

/// 노트와 독립적으로 보관하는 대화 한 건. 첫 요청을 보내기 전에는 초안이다.
public struct AgentConversation: Identifiable, Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let formatVersion: Int
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var targets: [NoteID]
    public var draft: String
    public var messages: [Message]
    public var requests: [AgentRequest]

    public struct Message: Codable, Equatable, Sendable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        public var role: Role
        public var requestID: UUID
        public var text: String
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, createdAt, updatedAt, targets, draft, messages, requests
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(targets, forKey: .targets)
        try c.encode(draft, forKey: .draft)
        try c.encode(messages, forKey: .messages)
        try c.encode(requests, forKey: .requests)
    }

    public var name: String {
        requests.first?.userText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "새 대화"
    }

    public init(targets: [NoteID], now: Date = Date()) {
        formatVersion = Self.currentVersion
        id = UUID()
        createdAt = now
        updatedAt = now
        self.targets = targets
        draft = ""
        messages = []
        requests = []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        guard formatVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .formatVersion, in: c,
                                                   debugDescription: "지원하지 않는 대화 형식입니다")
        }
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        targets = try c.decodeIfPresent([NoteID].self, forKey: .targets) ?? []
        draft = try c.decodeIfPresent(String.self, forKey: .draft) ?? ""
        messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        requests = try c.decodeIfPresent([AgentRequest].self, forKey: .requests) ?? []
    }
}

public struct AgentRequest: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case running, completed, interrupted, failed, awaitingAnswer }
    public struct Step: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case think, search, read, write }
        public var id: UUID
        public var kind: Kind
        public var startedAt: Date
        public var endedAt: Date?
        public var elapsed: TimeInterval?
        public var result: String?
        public var noteID: NoteID?
        public var noteTitle: String?
    }
    public var id: UUID
    public var runID: UUID
    public var engine: String
    public var model: String?
    public var status: Status
    public var userText: String
    public var answer: String?
    public var steps: [Step]
    public var proposals: [AgentProposal]
}
