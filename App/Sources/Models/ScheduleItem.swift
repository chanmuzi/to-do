import Foundation

/// 노트의 예정. EventKit 객체를 저장하거나 기능 모듈에 노출하지 않는다.
public struct ScheduleItem: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case reminder, event }
    public struct Link: Hashable, Codable, Sendable {
        public var localID: String
        public var externalID: String?
        public var kind: Kind?
        public init(localID: String, externalID: String?, kind: Kind? = nil) {
            self.localID = localID; self.externalID = externalID; self.kind = kind
        }
    }
    public var id: String
    public var start: Date
    public var end: Date?
    public var isDateOnly: Bool
    public var isCompleted: Bool
    public var title: String
    public var inlineSource: InlineScheduleSource?
    public var todo: TodoAnchor?
    public var link: Link?
    public var modified: Date
    public var pendingCalendarID: String?
    public var syncedAt: Date?
    /// 시간 정밀도가 낮은 외부 저장소도 같은 초의 변경을 놓치지 않도록 마지막 동기화 값을 비교한다.
    public var syncBaseline: Value?
    public struct Value: Hashable, Codable, Sendable {
        public let start: Date
        public let end: Date?
        public let dateOnly: Bool
        public let completed: Bool
        public let title: String
    }
    public var value: Value { Value(start: start, end: end, dateOnly: isDateOnly, completed: isCompleted, title: title) }
    public var syncError: String?
    /// 삭제 실패/오프라인에서도 연결을 잃지 않고 다음 동기화에서 다시 삭제한다.
    public var isDeleted: Bool
    public var kind: Kind { end == nil ? .reminder : .event }

    public init(id: String = UUID().uuidString, start: Date, end: Date? = nil,
                isDateOnly: Bool = false, isCompleted: Bool = false, title: String = "",
                todo: TodoAnchor? = nil, inlineSource: InlineScheduleSource? = nil, link: Link? = nil, modified: Date = Date(),
                syncedAt: Date? = nil, syncBaseline: Value? = nil, syncError: String? = nil, isDeleted: Bool = false) {
        self.inlineSource = inlineSource
        self.id = id; self.start = start; self.end = end; self.isDateOnly = isDateOnly
        self.isCompleted = isCompleted; self.title = title; self.todo = todo; self.link = link
        self.modified = modified; self.syncedAt = syncedAt; self.syncBaseline = syncBaseline; self.syncError = syncError; self.isDeleted = isDeleted
    }

    private enum CodingKeys: String, CodingKey {
        case pendingCalendarID, id, start, end, isDateOnly, isCompleted, title, todo, inlineSource, link, modified, syncedAt, syncBaseline, syncError, isDeleted
    }
    private enum KindKey: String, CodingKey { case kind }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(pendingCalendarID, forKey: .pendingCalendarID)
        try c.encode(id, forKey: .id); try c.encode(start, forKey: .start); try c.encodeIfPresent(end, forKey: .end)
        try c.encode(isDateOnly, forKey: .isDateOnly); try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(inlineSource, forKey: .inlineSource)
        try c.encode(title, forKey: .title); try c.encodeIfPresent(todo, forKey: .todo); try c.encodeIfPresent(link, forKey: .link)
        try c.encode(modified, forKey: .modified); try c.encodeIfPresent(syncedAt, forKey: .syncedAt)
        try c.encodeIfPresent(syncBaseline, forKey: .syncBaseline)
        try c.encodeIfPresent(syncError, forKey: .syncError); try c.encode(isDeleted, forKey: .isDeleted)
        var type = encoder.container(keyedBy: KindKey.self)
        try type.encode(kind, forKey: .kind)
    }

    public func isUpcoming(at now: Date, calendar: Calendar = .current) -> Bool {
        !isDeleted && !isCompleted && (isDateOnly
            ? calendar.startOfDay(for: start) >= calendar.startOfDay(for: now) : start >= now)
    }
}

/// 원문은 바꾸지 않고 줄 번호와 정확한 투두 글자로 연결한다. 중복되어 모호하면 추측해서 체크하지 않는다.
public struct TodoAnchor: Hashable, Codable, Sendable {
    public var line: Int
    public var text: String
    public init(line: Int, text: String) { self.line = line; self.text = text }
    public init?(line: Int, sourceLine: String) {
        guard let parts = Self.parts(sourceLine) else { return nil }
        self.init(line: line, text: parts.text)
    }

    public func locate(in body: String) -> Int? {
        let lines = body.components(separatedBy: "\n")
        var insideFence = false
        var matches: [Int] = []
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { insideFence.toggle(); continue }
            if !insideFence && Self.parts(lines[index])?.text == text { matches.append(index) }
        }
        return matches.count == 1 ? matches[0] : nil
    }
    public func completed(in body: String) -> Bool? {
        guard let index = locate(in: body) else { return nil }
        return Self.parts(body.components(separatedBy: "\n")[index])?.completed
    }
    public func settingCompleted(_ completed: Bool, in body: String) -> String {
        guard let index = locate(in: body) else { return body }
        var lines = body.components(separatedBy: "\n")
        guard let range = lines[index].range(of: #"\[[ xX]\]"#, options: .regularExpression) else { return body }
        lines[index].replaceSubrange(range, with: completed ? "[x]" : "[ ]")
        return lines.joined(separator: "\n")
    }
    private static func parts(_ line: String) -> (text: String, completed: Bool)? {
        guard let range = line.range(of: #"^\s*(?:- )?\[[ xX]\] "#, options: .regularExpression) else { return nil }
        let prefix = String(line[range])
        return (String(line[range.upperBound...]), prefix.contains("[x]") || prefix.contains("[X]"))
    }
}
