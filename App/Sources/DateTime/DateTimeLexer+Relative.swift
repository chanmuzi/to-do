import Foundation

/// 지금부터 얼마 뒤, 며칠 뒤를 찾는 무늬. `전`으로 끝나는 지난 때와 되풀이를 뜻하는 말도 여기서 가려낸다.
nonisolated extension DateTimeLexer {
    private static let direction = #"\s*(뒤|후|있다가|전)"# + wordEnd

    /// `전`이면 지난 때다. 리마인더가 될 수 없다.
    private static func isPast(_ word: String?) -> Bool { word == "전" }

    private static func fromNow(seconds: Double) -> DateTimePiece? {
        seconds > 0 ? piece(.fromNow(seconds)) : nil
    }

    /// 2시간 30분, 1시간 반. 모둠: `minutes`번이 분, `half`번이 반.
    private static func hoursAndMinutes(_ hours: Double, _ match: Match, minutes: Int, half: Int) -> Double {
        (hours + (match.has(half) ? 0.5 : 0)) * 3600 + Double(match.int(minutes) ?? 0) * 60
    }

    private static func days(_ amount: Int, unit: String?) -> DateSpec? {
        guard amount > 0, let unit else { return nil }
        switch unit {
        case "일": return .offsetDays(amount)
        case "주", "주일": return .offsetDays(amount * 7)
        case "달", "개월": return .offsetMonths(amount)
        case "년": return .offsetMonths(amount * 12)
        default: return nil
        }
    }

    static let relativeRules: [Rule] = [
        // 2시간 뒤, 1시간 30분 후, 1시간 반 뒤, 1.5시간 뒤, 3시간 전(지난 때)
        Rule(#"(?<![\d.])(\d{1,3}(?:\.5)?)\s*시간(?:\s*(\d{1,2})\s*분|\s*(반))?"# + direction) { match in
            guard let hours = match.string(1).flatMap(Double.init) else { return nil }
            if isPast(match.string(4)) { return date(.void) }
            return fromNow(seconds: hoursAndMinutes(hours, match, minutes: 2, half: 3))
        },
        // 한 시간 뒤, 두시간 후, 한 시간 반 뒤, 반시간 뒤
        Rule(#"(?<![가-힣])("# + KoreanNumeral.hourPattern + #"|반)\s?시간(?:\s*(\d{1,2})\s*분|\s*(반))?"#
            + direction) { match in
            guard let word = match.string(1) else { return nil }
            let hours = word == "반" ? 0.5 : KoreanNumeral.hour(word).map(Double.init)
            guard let hours else { return nil }
            if isPast(match.string(4)) { return date(.void) }
            return fromNow(seconds: hoursAndMinutes(hours, match, minutes: 2, half: 3))
        },
        // 30분 뒤, 5분 전(지난 때)
        Rule(#"(?<![\d.])(\d{1,3})\s*분"# + direction) { match in
            guard let minutes = match.int(1) else { return nil }
            if isPast(match.string(2)) { return date(.void) }
            return fromNow(seconds: Double(minutes) * 60)
        },
        // in 2 hours, in 30 min, in an hour, in an hour and a half, in 1.5 hours, in half an hour
        Rule(#"(?<![A-Za-z0-9])in\s+(\d{1,3}(?:\.\d)?|an?|half\s+an?)\s*(minutes?|mins?|hours?|hrs?)"#
            + #"(\s+and\s+a\s+half)?(?![A-Za-z0-9])"#, caseInsensitive: true) { match in
            guard let word = match.string(1)?.lowercased(), let unit = match.string(2)?.lowercased() else { return nil }
            let amount = Double(word) ?? (word.hasPrefix("half") ? 0.5 : 1)
            return fromNow(seconds: (amount + (match.has(3) ? 0.5 : 0)) * (unit.hasPrefix("m") ? 60 : 3600))
        },
        // 3일 뒤, 2주 후, 3개월 뒤, 2일 전(지난 때)
        Rule(#"(?<![\d.])(\d{1,3})\s*(일|주일?|달|개월|년)"# + direction) { match in
            guard let amount = match.int(1) else { return nil }
            if isPast(match.string(3)) { return date(.void) }
            return days(amount, unit: match.string(2)).map { date($0) }
        },
        // 일주일 뒤, 이주 후, 한달 뒤, 두 달 뒤
        Rule(#"(?<![가-힣])("# + KoreanNumeral.countPattern + #")\s?(주일?|달)"# + direction) { match in
            guard let amount = match.string(1).flatMap(KoreanNumeral.count) else { return nil }
            if isPast(match.string(3)) { return date(.void) }
            return days(amount, unit: match.string(2)).map { date($0) }
        },
        // 하루 뒤, 이틀 후
        Rule(#"(?<![가-힣])("# + KoreanNumeral.dayPattern + ")" + direction) { match in
            guard let amount = match.string(1).flatMap(KoreanNumeral.days) else { return nil }
            return isPast(match.string(2)) ? date(.void) : date(.offsetDays(amount))
        },
        // in 3 days, in a week, in 2 months
        Rule(#"(?<![A-Za-z0-9])in\s+(\d{1,3}|an?)\s*(days?|weeks?|months?)(?![A-Za-z0-9])"#,
             caseInsensitive: true) { match in
            let amount = match.int(1) ?? 1
            guard amount > 0, let unit = match.string(2)?.lowercased() else { return nil }
            if unit.hasPrefix("m") { return date(.offsetMonths(amount)) }
            return date(.offsetDays(amount * (unit.hasPrefix("w") ? 7 : 1)))
        },

        // 지난 때를 가리키는 말. 뒤따르는 날과 시각까지 가져가 리마인더가 되지 않게 한다.
        Rule(#"(?<![가-힣])(어제|그저께|그제|엊그제|그끄저께|작년|지난해|재작년|(?:지난|저번)\s?(?:주|달|해))"#) { _ in
            date(.void)
        },
        Rule(#"(?<![A-Za-z0-9])(?:yesterday|last\s+(?:night|week|month|year)|"#
            + #"(?:\d{1,3}|an?)\s+(?:minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\s+ago)(?![A-Za-z0-9])"#,
             caseInsensitive: true) { _ in
            date(.void)
        },

        // 되풀이. `매주 금요일`, `매달 20일`은 읽지 않는다. `매일 9시`만 다가오는 한 번으로 읽는다.
        Rule(#"(?<![가-힣])(매주|매달|매월|매년|격주|격일)"#) { _ in date(.void) },
        Rule(#"(?<![A-Za-z0-9])(?:every\s+(?:other\s+)?(?:week|month|year|weekday|"# + englishWeekdayPattern
            + #")s?|weekly|biweekly|monthly|yearly)(?![A-Za-z0-9])"#, caseInsensitive: true) { _ in
            date(.void)
        },
        Rule(#"(?<![가-힣])(매일|날마다)"#) { _ in piece(.daily) },
        Rule(#"(?<![A-Za-z0-9])(every\s?day|daily)(?![A-Za-z0-9])"#, caseInsensitive: true) { _ in piece(.daily) },
    ]
}
