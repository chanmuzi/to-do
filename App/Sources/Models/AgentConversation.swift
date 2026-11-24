import Foundation

/// 노트와 독립적으로 보관하는 대화 한 건. 첫 요청을 보내기 전에는 초안이다.
public struct AgentConversation: Identifiable, Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let formatVersion: Int
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var targets: [NoteID]
    public var customName: String?
    public var seenAt: Date?
    public var needsAnswer: Bool { requests.contains { $0.status == .awaitingAnswer } }
    public var draft: String
    public struct Queued: Identifiable, Codable, Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let order: Int64?
        public var heldAfterFailure: Bool?
        package init(text: String, id: UUID = UUID(), order: Int64? = nil, held: Bool? = nil) {
            self.id = id
            self.text = text
            self.order = order
            self.heldAfterFailure = held
        }
    }
    public var queued: [Queued] = []
    public var messages: [Message]
    public var requests: [AgentRequest]

    public struct Message: Codable, Equatable, Sendable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        package init(role: Role, requestID: UUID, text: String) { self.role = role; self.requestID = requestID; self.text = text }
        public var role: Role
        public var requestID: UUID
        public var text: String
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, createdAt, updatedAt, targets, draft, messages, requests, queued, seenAt, customName
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(seenAt, forKey: .seenAt)
        try c.encodeIfPresent(customName, forKey: .customName)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(targets, forKey: .targets)
        try c.encode(queued, forKey: .queued)
        try c.encode(draft, forKey: .draft)
        try c.encode(messages, forKey: .messages)
        try c.encode(requests, forKey: .requests)
    }

    package var hasSubmitted: Bool { !requests.isEmpty || !queued.isEmpty }

    /// 중단 표시와 맨 앞의 재전송 예약은 한 번의 대화 파일 저장으로 확정한다.
    package mutating func interruptForShutdown(at index: Int) {
        requests[index].status = .interrupted
        requests[index].stopReason = .shutdown
        let request = requests[index]
        if !queued.contains(where: { $0.id == request.id }) {
            queued.insert(Queued(text: request.userText, id: request.id, order: 0), at: 0)
        }
    }

    public var name: String {
        customName ?? (requests.first?.userText ?? queued.first?.text).flatMap(NotePreviewText.firstLine) ?? "새 대화"
    }

    package func completionMessage(for request: AgentRequest) -> String {
        customName ?? request.answer.flatMap(NotePreviewText.firstLine) ?? "끝났어요"
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
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        seenAt = try c.decodeIfPresent(Date.self, forKey: .seenAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        targets = try c.decodeIfPresent([NoteID].self, forKey: .targets) ?? []
        draft = try c.decodeIfPresent(String.self, forKey: .draft) ?? ""
        queued = try c.decodeIfPresent([Queued].self, forKey: .queued) ?? []
        messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        requests = try c.decodeIfPresent([AgentRequest].self, forKey: .requests) ?? []
    }
}

public struct AgentRequest: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case running, completed, interrupted, failed, awaitingAnswer }
    public struct Step: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case think, search, read, write }
        public var callID: String?
        public var id: UUID
        public var kind: Kind
        public var startedAt: Date
        public var endedAt: Date?
        public var elapsed: TimeInterval?
        public var result: String?
        public var noteID: NoteID?
        public var noteTitle: String?
        package init(_ kind: Kind, callID: String? = nil, now: Date = Date()) {
            self.id = UUID()
            self.kind = kind
            self.startedAt = now
            self.callID = callID
        }
    }
    public var id: UUID
    public enum StopReason: String, Codable, Sendable { case user, shutdown }
    public struct StoppedAttempt: Identifiable, Codable, Equatable, Sendable {
        public let id: UUID
        public let steps: [Step]
        public let answer: String?
        package init(_ request: AgentRequest) {
            id = request.runID
            steps = request.steps
            answer = request.answer
        }
    }
    public var failedThroughOrder: Int64?
    public var stopReason: StopReason?
    public var stoppedAttempts: [StoppedAttempt]?
    public var runID: UUID
    public var engine: String
    public var model: String?
    public var status: Status
    public var userText: String
    public var answer: String?
    public var steps: [Step]
    public var failure: String?
    public var resumeAt: Date?
    package var resumeTime: String? {
        resumeAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "ko_KR")))
    }
    public var proposals: [AgentProposal]
}

extension AgentRequest {
    package init(id: UUID, text: String, engine: String, model: String?) {
        self.init(id: id, runID: UUID(), engine: engine, model: model, status: .running,
                  userText: text, steps: [], proposals: [])
    }
}
