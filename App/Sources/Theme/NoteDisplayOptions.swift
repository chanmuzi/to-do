import Foundation

/// 상단 줄 표시 방식(spec 5.2). 설정 화면이 생기면 거기서 바꾼다. 기본값은 `tokens.json`의 `display.defaults`와 같다.
public struct NoteDisplayOptions: Hashable, Sendable {
    public enum SpaceDisplay: String, Hashable, Sendable {
        case icon, iconAndName, name
    }

    public enum ReminderDisplay: String, Hashable, Sendable {
        /// 시간("3:00 PM"). 오늘이 아니면 날짜를 앞에 붙인다.
        case time
        /// 남은 시간("12분 후").
        case relative
        case iconOnly
    }

    public enum ClockFormat: String, Hashable, Sendable {
        /// `3:00 PM`
        case twelveHour
        /// `오후 3:00`
        case koreanMeridiem
        /// `15:00`
        case twentyFourHour
    }

    public enum DateFormat: String, Codable, Hashable, Sendable { case relative, absolute }

    public enum HeightMode: String, Codable, Sendable { case fixed, fitContent }
    public var heightMode: HeightMode = .fixed

    public enum FormatBar: String, Codable, Sendable { case always, editing, hidden }
    public var showsNoteAgent = true
    public var formatBar: FormatBar = .hidden
    public var underlineMarkedText = false
    public var dateFormat: DateFormat
    public var space: SpaceDisplay
    public var reminder: ReminderDisplay
    public var clock: ClockFormat
    /// 리마인더가 "임박"이 되는 시점(초). 임시 값 15분(spec 20의 3번).
    public var imminentLeadTime: TimeInterval

    public init(
        dateFormat: DateFormat = .relative,
        space: SpaceDisplay = .icon,
        reminder: ReminderDisplay = .time,
        clock: ClockFormat = .koreanMeridiem,
        imminentLeadTime: TimeInterval = 15 * 60
    ) {
        self.dateFormat = dateFormat
        self.space = space
        self.reminder = reminder
        self.clock = clock
        self.imminentLeadTime = imminentLeadTime
    }
}
