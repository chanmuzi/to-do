import Foundation

/// ⌘R로 직접 고르는 리마인더(spec 7). 리마인더 고르는 화면이 생기기 전까지의 임시 방식(D-026):
/// 누를 때마다 다음 값으로 넘어가고, 마지막 다음에는 "직접 고르지 않음"(글에서 읽은 시간을 따름)으로 돌아간다.
nonisolated enum CaptureReminderPresets {
    /// 차례: 1시간 뒤, 오늘 저녁 6시(지났으면 뺀다), 내일 오전 9시, 다음 주 월요일 오전 9시.
    static func dates(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: today)
                .flatMap { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) }
        }
        let weekday = calendar.component(.weekday, from: today) - 1
        let untilMonday = (8 - weekday) % 7 == 0 ? 7 : (8 - weekday) % 7
        let candidates = [
            calendar.date(byAdding: .hour, value: 1, to: now),
            day(0, hour: 18),
            day(1, hour: 9),
            day(untilMonday, hour: 9),
        ]
        return candidates.compactMap { $0 }.filter { $0 > now }.reduce(into: [Date]()) { result, date in
            if !result.contains(date) { result.append(date) }
        }
    }

    /// 지금 고른 값 다음의 값. `nil`은 직접 고르지 않은 상태다.
    static func next(after current: Date?, now: Date, calendar: Calendar) -> Date? {
        let all = dates(now: now, calendar: calendar)
        guard let current else { return all.first }
        guard let index = all.firstIndex(of: current) else { return all.first { $0 > current } }
        return index + 1 < all.count ? all[index + 1] : nil
    }
}
