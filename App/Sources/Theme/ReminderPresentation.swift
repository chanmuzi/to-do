import Foundation
import Models

/// 상단 줄의 리마인더 표시(spec 5.2, 규칙 13: 한 번에 한 가지 정보만).
public struct ReminderPresentation: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case scheduled, imminent, overdue
    }

    public let status: Status
    public var isEvent = false
    public var syncFailed = false
    public var isDateOnly = false
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

    public init(item: ScheduleItem, now: Date, options: NoteDisplayOptions, calendar: Calendar) {
        isEvent = item.kind == .event
        syncFailed = item.syncError != nil
        isDateOnly = item.isDateOnly
        status = item.isDateOnly
            ? (calendar.startOfDay(for: item.start) < calendar.startOfDay(for: now) ? .overdue : .scheduled)
            : Self.status(reminder: item.start, now: now, leadTime: options.imminentLeadTime)
        if options.reminder == .iconOnly { text = nil }
        else if options.reminder == .relative {
            text = item.isDateOnly && calendar.isDate(item.start, inSameDayAs: now)
                ? "오늘" : Self.relative(reminder: item.start, now: now, calendar: calendar)
        } else if item.isDateOnly {
            let first = Self.dayLabel(item.start, now: now, calendar: calendar)
            if let end = item.end {
                let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
                text = calendar.isDate(last, inSameDayAs: item.start) ? first
                    : first + "~" + Self.dayLabel(last, now: now, calendar: calendar)
            } else { text = first }
        } else {
            let first = Self.dayPrefix(reminder: item.start, now: now, calendar: calendar)
                + Self.clock(item.start, format: options.clock, calendar: calendar)
            if let end = item.end {
                let sameDay = calendar.isDate(item.start, inSameDayAs: end)
                var last = Self.clock(end, format: options.clock, calendar: calendar)
                if sameDay && options.clock == .koreanMeridiem
                    && calendar.component(.hour, from: item.start) / 12 == calendar.component(.hour, from: end) / 12 {
                    last = String(last.dropFirst(3))
                }
                text = first + "~" + (sameDay ? "" : Self.dayPrefix(reminder: end, now: now, calendar: calendar)) + last
            } else { text = first }
        }
    }
    private static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "오늘"
            : dayPrefix(reminder: date, now: now, calendar: calendar).trimmingCharacters(in: .whitespaces)
    }
    public var accessibilityLabel: String {
        [isEvent ? "일정" : "리마인더", text ?? "", status == .imminent ? "임박" : "",
         syncFailed ? "연동 실패, 앱에 저장됨" : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 임박만 종, 나머지는 시계(spec 18.2).
    public var symbolName: String { isEvent ? "calendar" : (status == .imminent ? "bell" : "clock") }
    /// 예정은 상단 줄의 보조 글자색, 임박과 지남은 `warn`.
    public var color: ColorToken { status == .scheduled ? .text2 : .warn }
    /// 임박만 굵게. 세 상태의 글자 폭은 같다(고정폭 글꼴).
    public var textStyle: TextStyle { status == .imminent ? .uiStrong : .ui }
    public var isRinging: Bool { status == .imminent && !isEvent }

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
        if calendar.component(.year, from: reminder) != calendar.component(.year, from: now) {
            let parts = calendar.dateComponents([.year, .month, .day], from: reminder)
            return "\(parts.year!)/\(parts.month!)/\(parts.day!) "
        }
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
