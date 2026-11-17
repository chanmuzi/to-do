import Foundation

/// 캡처 바 오른쪽에 보이는 리마인더 글자: "내일 10:00 AM"(화면 3). 시간 형식은 `tokens.json`의 기본값(12시간제)이다.
///
/// 읽은 때가 다르게 읽힐 틈이 없게 적는다: 오전, 오후는 언제나 붙이고, 오늘이 아니면 날을, 올해가 아니면 해까지 적는다.
nonisolated enum CaptureReminderText {
    static func text(for reminder: Date, now: Date, calendar: Calendar) -> String {
        dayPrefix(reminder: reminder, now: now, calendar: calendar) + clock(reminder, calendar: calendar)
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = String(format: "%02d", parts.minute ?? 0)
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(minute) \(hour < 12 ? "AM" : "PM")"
    }

    /// 오늘이면 없음. 내일과 어제는 말로, 이레 안의 앞날은 요일로, 그 밖에는 월/일(다른 해면 해/월/일).
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
            let parts = calendar.dateComponents([.year, .month, .day], from: reminder)
            let monthDay = "\(parts.month ?? 0)/\(parts.day ?? 0) "
            let isThisYear = parts.year == calendar.component(.year, from: now)
            return isThisYear ? monthDay : "\(parts.year ?? 0)/" + monthDay
        }
    }
}
