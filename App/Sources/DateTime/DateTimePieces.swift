import Foundation

/// 하루 가운데 때를 가리키는 말.
nonisolated enum DayPart: Hashable, Sendable {
    /// 오전, am
    case morning
    /// 아침, morning
    case earlyMorning
    /// 새벽
    case dawn
    /// 낮, 점심
    case midday
    /// 오후, pm, afternoon
    case afternoon
    /// 저녁, evening
    case evening
    /// 밤, night, tonight
    case night

    init?(word: String) {
        switch word.lowercased() {
        case "오전", "am", "a": self = .morning
        case "아침", "morning": self = .earlyMorning
        case "새벽": self = .dawn
        case "낮", "점심": self = .midday
        case "오후", "pm", "p", "afternoon": self = .afternoon
        case "저녁", "evening": self = .evening
        case "밤", "night", "tonight": self = .night
        default: return nil
        }
    }

    /// 적은 시(1~12, 또는 24시간제 그대로)를 0시부터 센 시로 바꾼다. 24 이상은 다음 날이다(밤 12시, 밤 1시).
    /// 맞지 않는 짝(오전 15시, 아침 12시)은 `nil`.
    func hour24(_ hour: Int) -> Int? {
        switch (self, hour) {
        case (.morning, 12), (.dawn, 12): 0
        case (.morning, 0...11), (.dawn, 0...11), (.earlyMorning, 1...11): hour
        case (.midday, 10...12): hour
        case (.midday, 1...6): hour + 12
        case (.afternoon, 12): 12
        case (.afternoon, 1...11), (.evening, 1...11): hour + 12
        case (.afternoon, 13...23), (.evening, 13...23), (.night, 13...23): hour
        case (.evening, 12), (.night, 12), (.night, 0): 24
        case (.night, 1...5): hour + 24
        case (.night, 6...11): hour + 12
        default: nil
        }
    }
}

/// 시각을 적지 않았을 때 쓰는 값. 여기 한 곳에서만 정한다(spec 7a).
nonisolated enum DateTimeDefaults {
    /// 날만 적었을 때(`내일`, `11월 20일`).
    static let dateOnlyHour = 9
    /// 날과 함께 때를 가리키는 말만 적었을 때(`내일 저녁`).
    static let dayPartHours: [DayPart: Int] = [
        .dawn: 5, .earlyMorning: 8, .morning: 9, .midday: 12, .afternoon: 14, .evening: 19, .night: 21,
    ]

    static func hour(for part: DayPart?) -> Int {
        part.flatMap { dayPartHours[$0] } ?? dateOnlyHour
    }
}

/// 적은 시각.
nonisolated struct TimeSpec: Hashable, Sendable {
    var hour: Int
    var minute = 0
    /// 앞에 붙은 오전, 오후(또는 뒤의 am, pm, `7시 저녁에`).
    var part: DayPart?
    /// 24시간제로 적었다: 앞에 0을 붙인 `09:00`, 0시, 13~23시, `24:00`.
    var isClock24 = false
    /// `3시 5분 전`의 5. 읽은 시각에서 뺀다.
    var minutesBefore = 0
    /// 뒤에 붙은 시간대 이름(`PST`, ISO 표기의 `Z`, `+09:00`).
    var zone: String?

    /// 오전, 오후를 적지 않고 1~12시만 적었다. 어느 쪽인지 골라야 한다.
    var isBare: Bool { part == nil && !isClock24 }

    /// 고를 필요가 없는 시각의 시(0시부터, 24 이상은 다음 날).
    var definiteHour: Int? {
        if let part { return part.hour24(hour) }
        return isClock24 ? hour : nil
    }

    /// 오전, 오후를 적지 않았을 때 고르는 쪽: 1~7시는 오후, 8~11시는 오전, 12시는 정오(자정이 아니다).
    var preferredHour: Int {
        (1...7).contains(hour) ? hour + 12 : hour
    }

    /// 날에 붙은 때를 가리키는 말을 받는다(`내일 저녁 ... 7시`). 스스로 정해진 시각이거나 맞지 않는 짝이면 그대로다.
    func applying(_ outer: DayPart?) -> TimeSpec {
        guard isBare, let outer, outer.hour24(hour) != nil else { return self }
        var copy = self
        copy.part = outer
        return copy
    }
}

/// 적은 날.
nonisolated enum DateSpec: Hashable, Sendable {
    enum WeekScope: Hashable, Sendable {
        /// 요일만 적었다: 다가오는 그 요일(오늘이 그 요일이면 오늘).
        case upcoming
        /// 이번 주(월요일에 시작)에서 몇 주 뒤인지. 0이 이번 주.
        case weeksAhead(Int)
    }

    enum Year: Hashable, Sendable {
        case exact(Int)
        /// 올해에서 몇 해 뒤(`내년`은 1).
        case fromNow(Int)
    }

    /// 오늘에서 며칠 뒤(오늘 0, 내일 1, `3일 뒤`).
    case offsetDays(Int)
    /// 오늘에서 몇 달 뒤의 같은 날(`한달 뒤`).
    case offsetMonths(Int)
    /// 요일. `weekday`는 일요일이 0.
    case weekday(Int, WeekScope)
    /// 월과 일. 해를 적지 않았으면 오늘이거나 다가오는 그날.
    case monthDay(month: Int, day: Int, year: Year?, loose: Bool)
    /// 이번 달에서 몇 달 뒤의 며칠(`다음 달 20일`, `이번 달 15일`). 지났어도 그날이다.
    case monthOffsetDay(months: Int, day: Int)
    /// 날만(`20일`): 오늘이거나 다가오는 그날.
    case dayOfMonth(Int)
    /// 이번 달의 남은 날일 때만 날짜다(`20~22일`의 양 끝). 지난 날이면 기간으로 보고 읽지 않는다.
    case comingDayThisMonth(Int)
    /// 알아듣기는 했지만 리마인더가 될 수 없는 말: 지난 때(`어제`, `지난주 금요일`, `3일 전`)와 되풀이(`매주`).
    /// 바로 뒤의 날과 시각을 함께 가져가 다른 뜻으로 읽히지 않게 한다.
    case void
}

/// 글에서 찾은 조각 하나.
nonisolated struct DateTimePiece: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case date(DateSpec)
        case time(TimeSpec)
        /// 한 덩어리로 적은 날과 시각(`2026-11-20T15:00:00`).
        case dateTime(DateSpec, TimeSpec)
        /// 한 덩어리로 적은 날의 범위(`20~22일`, `11월 20~22일`).
        case dateSpan(DateSpec, DateSpec)
        /// 지금부터 얼마 뒤(`30분 뒤`, `in 2 hours`). 초.
        case fromNow(TimeInterval)
        /// 시각에 붙지 않은 때를 가리키는 말(`내일 저녁 약속`의 `저녁`). 날 바로 뒤에 있을 때만 쓴다.
        case dayPart(DayPart)
        /// 날 뒤에 덧붙인 요일(`11/20(금)`). 날 바로 뒤에 있을 때 표현에 넣기만 한다.
        case weekdayNote
        /// `매일`, `every day`. 바로 뒤의 시각과 함께일 때만 쓴다.
        case daily
    }

    /// 혼자서는 읽지 않는 꼴.
    enum Requirement: Hashable, Sendable {
        case none
        /// `오늘`, `today`: 시각이나 때를 가리키는 말 없이는 뜻이 없다.
        case needsTime
        /// `11.20`, `sun`, `sat`: 소수나 보통 낱말과 가려지지 않는다. 시각이나 범위와 함께일 때만.
        case needsCompany
        /// `at 10`: 날과 함께일 때만 시각이다.
        case needsDate
    }

    var kind: Kind
    var range: NSRange
    var requirement: Requirement = .none
    /// 날을 가리키는 말에 든 때(`tonight`의 밤).
    var impliedPart: DayPart?
}
