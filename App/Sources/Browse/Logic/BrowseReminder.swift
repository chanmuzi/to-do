import Foundation
import Theme

/// 줄에 보이는 리마인더(spec 8): 아이콘과 시간. 임박(15분 전부터, spec 20의 3번 임시 값)은 종과 `warn`, 굵게.
nonisolated struct BrowseReminder: Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case scheduled, imminent, overdue
    }

    static let imminentLeadTime: TimeInterval = 15 * 60

    let status: Status
    let text: String

    init(reminder: Date, now: Date, calendar: Calendar) {
        if now >= reminder {
            status = .overdue
        } else {
            status = reminder.timeIntervalSince(now) <= Self.imminentLeadTime ? .imminent : .scheduled
        }
        text = Self.dayPrefix(reminder: reminder, now: now, calendar: calendar) + Self.clock(reminder, calendar: calendar)
    }

    var symbolName: String { status == .imminent ? "bell" : "clock" }
    var color: ColorToken { status == .scheduled ? .text2 : .warn }
    var isStrong: Bool { status == .imminent }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = String(format: "%02d", parts.minute ?? 0)
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(minute) \(hour < 12 ? "AM" : "PM")"
    }

    /// 오늘이면 없음. 내일과 어제는 말로, 이레 안의 앞날은 요일로, 그 밖에는 월/일.
    private static func dayPrefix(reminder: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: reminder)
        ).day ?? 0
        switch days {
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
}
