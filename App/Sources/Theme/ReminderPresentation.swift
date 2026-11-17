import Foundation

/// 상단 줄의 리마인더 표시(spec 5.2, 규칙 13: 한 번에 한 가지 정보만).
public struct ReminderPresentation: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case scheduled, imminent, overdue
    }

    public let status: Status
    /// 아이콘 옆 글자. 아이콘만 보이는 방식이면 `nil`.
    public let text: String?

    public init(reminder: Date, now: Date, options: NoteDisplayOptions, calendar: Calendar) {
        status = Self.status(reminder: reminder, now: now, leadTime: options.imminentLeadTime)
        switch options.reminder {
        case .iconOnly:
            text = nil
        case .time:
            text = Self.dayPrefix(reminder: reminder, now: now, calendar: calendar)
                + Self.clock(reminder, format: options.clock, calendar: calendar)
        case .relative:
            text = Self.relative(reminder: reminder, now: now, calendar: calendar)
        }
    }

    /// 임박만 종, 나머지는 시계(spec 18.2).
    public var symbolName: String { status == .imminent ? "bell" : "clock" }
    /// 예정은 상단 줄의 보조 글자색, 임박과 지남은 `warn`.
    public var color: ColorToken { status == .scheduled ? .text2 : .warn }
    /// 임박만 굵게. 세 상태의 글자 폭은 같다(고정폭 글꼴).
    public var textStyle: TextStyle { status == .imminent ? .uiStrong : .ui }
    public var isRinging: Bool { status == .imminent }

    public static func status(reminder: Date, now: Date, leadTime: TimeInterval) -> Status {
        if now >= reminder { return .overdue }
        return reminder.timeIntervalSince(now) <= leadTime ? .imminent : .scheduled
    }

    /// 표시가 달라지는 다음 시각. 그때 다시 그린다.
    public static func nextRefresh(
        reminder: Date, now: Date, options: NoteDisplayOptions, calendar: Calendar
    ) -> Date? {
        var candidates = [reminder.addingTimeInterval(-options.imminentLeadTime), reminder]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            candidates.append(tomorrow)
        }
        if options.reminder == .relative, reminder > now {
            let intoMinute = reminder.timeIntervalSince(now).truncatingRemainder(dividingBy: 60)
            candidates.append(now.addingTimeInterval(intoMinute > 0 ? intoMinute : 60))
        }
        return candidates.filter { $0 > now }.min()
    }

    // MARK: - 글자

    public static func clock(_ date: Date, format: NoteDisplayOptions.ClockFormat, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = String(format: "%02d", parts.minute ?? 0)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        switch format {
        case .twelveHour: return "\(twelve):\(minute) \(hour < 12 ? "AM" : "PM")"
        case .koreanMeridiem: return "\(hour < 12 ? "오전" : "오후") \(twelve):\(minute)"
        case .twentyFourHour: return "\(hour):\(minute)"
        }
    }

    /// 오늘이면 없음. 내일과 어제는 말로, 이레 안의 앞날은 요일로, 그 밖에는 월/일.
    public static func dayPrefix(reminder: Date, now: Date, calendar: Calendar) -> String {
        switch dayDistance(from: now, to: reminder, calendar: calendar) {
        case 0: return ""
        case 1: return "내일 "
        case -1: return "어제 "
        case 2...6:
            let weekday = calendar.component(.weekday, from: reminder)
            return ["일", "월", "화", "수", "목", "금", "토"][(weekday - 1) % 7] + " "
        default:
            let parts = calendar.dateComponents([.month, .day], from: reminder)
            return "\(parts.month ?? 0)/\(parts.day ?? 0) "
        }
    }

    public static func relative(reminder: Date, now: Date, calendar: Calendar) -> String {
        guard reminder > now else { return "지남" }
        let minutes = Int((reminder.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "\(max(minutes, 1))분 후" }
        let days = dayDistance(from: now, to: reminder, calendar: calendar)
        switch days {
        case 0: return "\(minutes / 60)시간 후"
        case 1: return "내일"
        default: return "\(days)일 후"
        }
    }

    private static func dayDistance(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)
        ).day ?? 0
    }
}
