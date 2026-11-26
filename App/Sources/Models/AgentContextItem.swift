import Foundation

/// 고른 하루는 시각이 아니다. 시간대가 바뀌어도 같은 현지 날짜를 가리킨다.
public struct AgentContextDay: Hashable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    func date(in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

public enum AgentContextItem: Hashable, Codable, Sendable {
    public enum Scope: String, Codable, Sendable { case today, pinned }
    public enum Period: Hashable, Codable, Sendable {
        case today, thisWeek, lastSevenDays, day(AgentContextDay)

        public func interval(at now: Date, calendar: Calendar) -> DateInterval? {
            switch self {
            case .today: return calendar.dateInterval(of: .day, for: now)
            case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now)
            case .lastSevenDays:
                let today = calendar.startOfDay(for: now)
                guard let start = calendar.date(byAdding: .day, value: -6, to: today),
                      let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
                return DateInterval(start: start, end: end)
            case .day(let day):
                return day.date(in: calendar.timeZone).flatMap { calendar.dateInterval(of: .day, for: $0) }
            }
        }
    }
    case note(NoteID), space(SpaceID), view(Scope), period(Period)

    public var librarySelection: LibrarySelection? {
        switch self {
        case .space(let id): .space(id)
        case .view(.today): .today
        case .view(.pinned): .floating
        default: nil
        }
    }

    public func name(notes: [NoteID: Note], spaces: [SpaceID: Space]) -> String {
        switch self {
        case .note(let id): notes[id].map { $0.title.isEmpty ? "제목 없음" : $0.title } ?? "없는 노트"
        case .space(let id): spaces[id]?.name ?? "없는 스페이스"
        case .view(.today), .period(.today): "오늘"
        case .view(.pinned): "고정됨"
        case .period(.thisWeek): "이번 주"
        case .period(.lastSevenDays): "지난 7일"
        case .period(.day(let day)): "\(day.month)월 \(day.day)일"
        }
    }
}
