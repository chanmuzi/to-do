import Foundation

/// 하루 가운데 때를 가리키는 말.
nonisolated enum DayPart: Hashable, Sendable {
    /// 오전, 아침, am
    case morning
    /// 새벽
    case dawn
    /// 오후, 낮, 점심, pm
    case afternoon
    /// 저녁
    case evening
    /// 밤
    case night

    init?(word: String) {
        switch word.lowercased() {
        case "오전", "아침", "am", "a": self = .morning
        case "새벽": self = .dawn
        case "오후", "낮", "점심", "pm", "p": self = .afternoon
        case "저녁": self = .evening
        case "밤": self = .night
        default: return nil
        }
    }

    /// 적은 시(1~12, 또는 24시간제 그대로)를 0시부터 센 시로 바꾼다. 24 이상은 다음 날이다(밤 12시, 밤 1시).
    /// 맞지 않는 짝(오전 15시)은 `nil`.
    func hour24(_ hour: Int) -> Int? {
        switch self {
        case .morning, .dawn:
            guard (0...12).contains(hour) else { return nil }
            return hour == 12 ? 0 : hour
        case .afternoon:
            guard (1...23).contains(hour) else { return nil }
            return hour < 12 ? hour + 12 : hour
        case .evening:
            guard (1...23).contains(hour) else { return nil }
            if hour == 12 { return 24 }
            return hour < 12 ? hour + 12 : hour
        case .night:
            guard (1...24).contains(hour) else { return nil }
            switch hour {
            case 12: return 24
            case 1...5: return 24 + hour
            case 6...11: return hour + 12
            default: return hour
            }
        }
    }
}

/// 적은 시각.
nonisolated struct TimeSpec: Hashable, Sendable {
    var hour: Int
    var minute: Int
    /// 앞에 붙은 오전·오후(또는 뒤의 am·pm).
    var part: DayPart?
    /// 시각 뒤에 따라온 때를 가리키는 말(`7시 저녁 약속`). 글자로는 차지하지 않고 읽을 때만 쓴다.
    var trailingPart: DayPart?

    /// 오전·오후를 적지 않고 1~12시만 적었다. 어느 쪽인지 골라야 한다.
    var isBare: Bool { part == nil && trailingPart == nil && (1...12).contains(hour) }

    /// 고를 필요가 없는 시각의 시(0시부터, 24 이상은 다음 날).
    var definiteHour: Int? {
        if let part = part ?? trailingPart { return part.hour24(hour) }
        return isBare ? nil : hour
    }

    /// 오전·오후를 적지 않았을 때의 후보(이른 것부터). 1~5시는 오후만, 6~11시는 오전과 오후, 12시는 정오와 자정.
    var bareCandidates: [Int] {
        switch hour {
        case 1...5: [hour + 12]
        case 12: [12, 24]
        default: [hour, hour + 12]
        }
    }

    /// 다른 날의 시각으로 적었을 때 고르는 쪽: 1~6시는 오후, 7~11시는 오전, 12시는 정오.
    var bareDefault: Int {
        switch hour {
        case 1...6: hour + 12
        default: hour
        }
    }
}

/// 적은 날.
nonisolated enum DateSpec: Hashable, Sendable {
    enum WeekScope: Hashable, Sendable {
        /// 요일만 적었다: 다가오는 그 요일.
        case upcoming
        /// 이번 주(월요일에 시작)에서 몇 주 뒤인지. 0이 이번 주.
        case weeksAhead(Int)
    }

    /// 오늘에서 며칠 뒤(오늘 0, 내일 1, `3일 뒤`).
    case offsetDays(Int)
    /// 요일. `weekday`는 일요일이 0.
    case weekday(Int, WeekScope)
    /// 월과 일. 해를 적었으면 그 해.
    case monthDay(month: Int, day: Int, year: Int?, loose: Bool)
    /// 날만(`20일`).
    case dayOfMonth(Int)
}

/// 글에서 찾은 조각 하나.
nonisolated struct DateTimePiece: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case date(DateSpec)
        case time(TimeSpec)
        /// 지금부터 얼마 뒤(`30분 뒤`, `in 2 hours`). 초.
        case fromNow(TimeInterval)
    }

    /// 날짜만으로는 읽지 않는 꼴. 시각이나 범위와 함께 있을 때만 쓴다.
    enum Requirement: Hashable, Sendable {
        case none
        /// `오늘`, `today`: 시각 없이는 뜻이 없다.
        case needsTime
        /// `11.20`, `sun`, `sat`: 소수나 보통 낱말과 가려지지 않는다.
        case needsCompany
    }

    var kind: Kind
    var range: NSRange
    var requirement: Requirement = .none
}
