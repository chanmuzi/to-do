import Foundation

/// 범위 조회로 가져온 일정 한 회차와 그 캘린더의 표시 정보.
public struct CalendarEvent: Hashable, Sendable {
    public let item: ScheduleItem
    public let destination: ScheduleDestination?
    public let recurring: Bool
    public init(item: ScheduleItem, destination: ScheduleDestination?, recurring: Bool = false) {
        self.item = item
        self.destination = destination
        self.recurring = recurring
    }
    public var calendarURL: URL? {
        guard let id = item.link?.localID, !id.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var url = URL(string: "ical://ekevent")!
        url.append(component: formatter.string(from: item.start))
        url.append(component: id)
        return url.appending(queryItems: [.init(name: "method", value: "show"), .init(name: "options", value: "more")])
    }
}
