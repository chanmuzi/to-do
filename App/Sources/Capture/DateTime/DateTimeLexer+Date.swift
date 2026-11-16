import Foundation

/// 날을 찾는 무늬. 날 뒤에 붙는 요일 덧말(`(금)`)과 때를 가리키는 말(`내일 저녁`)도 여기서 찾는다.
nonisolated extension DateTimeLexer {
    /// `오늘`, `내일` 뒤가 낱말의 끝일 때만(`내일배움카드`, `모레노`는 아니다). 때를 가리키는 말은 붙여 써도 된다(`오늘밤`).
    private static let dayWordEnd = #"(?=$|[^가-힣]|은|는|이|가|도|에|의|까지|부터|쯤|중|엔|"# + dayParts + ")"
    /// 날을 세는 말이 아닌 꼴: 기간과 차례(`20일간`, `3일째`, `2일 전`), 횟수와 상품 이름(`30일 챌린지`, `7일 무료`, `3일 연속`).
    private static let notADay = #"(?!간|동안|째|차|치|분|\s*(?:뒤|후|전)"# + wordEnd
        + #"|\s*(?:동안|간|이상|이내|정도|씩|마다|만에|챌린지|무료|연속|체험|완성|과정|코스|걸림|걸려|걸린|소요|예상|내로|안에))"#
    /// 분수나 점수로 읽힐 말이 뒤따르면 날짜가 아니다(`1/2 완료`, `1/4분기`, `2/3 찬성`).
    private static let notAFraction = #"(?!\s*(?:완료|진행|정도|쯤|스푼|큰술|작은술|분량|분기|지점|확률|페이지|만큼|가량|크기|사이즈"#
        + #"|찬성|반대|완성|달성|통과|득표|박자|인치|(?:개|배|쪽|씩|점|컵)(?![가-힣])))"#
    /// 단위가 뒤따르면 소수다(`2.5배`, `4.5점`).
    private static let notADecimal = #"(?=$|[^가-힣A-Za-z]|까지|부터|에(?![가-힣]))"#
        + #"(?!\s*(?:배|점|개|%|kg|cm|mm|km|m|초|분|시간|만|억|천|원|도|인치|리터|L|GB|MB)(?![가-힣A-Za-z]))"#

    /// `2박 3일`, `주 5일`, `D-3일`, `3~5일`의 끝(범위 무늬가 따로 읽는다).
    private static let countBeforeDay = regex(#"(?:박\s*|(?<![가-힣])주\s*|[A-Za-z][-+]|\d\s*[~-]\s*)$"#)
    /// `1일 1커밋`, `1일 3회`: `1일` 뒤에 수와 단위가 오면 "하루에 몇 번"이다. 시각(`1일 3시`, `1일 3pm`)은 아니다.
    private static let countAfterDay = regex(#"\s*\d+\s*(?![aApP]\.?[mM]\b)(?!시|월|일)[가-힣A-Za-z]"#)

    private static let months = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]
    private static let monthPattern = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?"
        + "|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"

    private static func month(_ word: String?) -> Int? {
        word.flatMap { months.firstIndex(of: String($0.lowercased().prefix(3))) }.map { $0 + 1 }
    }

    /// `이번 주`, `다음주`, `담주`, `차주`, `다다음 주`가 몇 주 뒤인지. 지난 주는 `nil`.
    private static func weeksAhead(_ word: String) -> Int? {
        switch word.filter({ !$0.isWhitespace }) {
        case "이번주": 0
        case "다음주", "담주", "차주": 1
        case "다다음주": 2
        default: nil
        }
    }

    private static let weekWords = #"이번\s?주|다음\s?주|담\s?주|차주|다다음\s?주"#

    private static func monthDay(_ month: Int?, _ day: Int?, year: DateSpec.Year? = nil, loose: Bool = false) -> DateSpec? {
        guard let month, let day else { return nil }
        return .monthDay(month: month, day: day, year: year, loose: loose)
    }

    static let dateRules: [Rule] = [
        // 오늘, 내일, 모레, 글피, 내일모레(= 모레)
        Rule(#"(?<![가-힣])(내일\s?모레|낼\s?모레|오늘|내일|모레|글피)"# + dayWordEnd) { match in
            switch match.string(1) {
            case "오늘": date(.offsetDays(0), requirement: .needsTime)
            case "내일": date(.offsetDays(1))
            case "글피": date(.offsetDays(3))
            default: date(.offsetDays(2))
            }
        },
        // 낼: `낼 수 있다`와 가려지지 않아 수나 때를 가리키는 말이 뒤따를 때만.
        Rule(#"(?<![가-힣])낼(?=\s*(?:\d|까지|부터|"# + dayParts + "))") { _ in date(.offsetDays(1)) },
        Rule(#"(?<![A-Za-z0-9])(today|tomorrow|tmrw|tmr)(?![A-Za-z0-9])"#, caseInsensitive: true) { match in
            match.string(1)?.lowercased() == "today"
                ? date(.offsetDays(0), requirement: .needsTime) : date(.offsetDays(1))
        },
        // tonight, this evening: 오늘의 그 무렵.
        Rule(#"(?<![A-Za-z0-9])(?:(tonight)|this\s+(morning|afternoon|evening))(?![A-Za-z0-9'])"#,
             caseInsensitive: true) { match in
            piece(.date(.offsetDays(0)), impliedPart: (match.string(1) ?? match.string(2)).flatMap(DayPart.init(word:)))
        },

        // 금요일, 금욜, 이번 주 금요일, 다음 주 월요일, 담주 금요일, 차주 금요일, 지난주 금요일(지난 때)
        Rule(#"(?<![가-힣])(?:("# + weekWords + #"|지난\s?주|저번\s?주|지난|저번)\s*)?([월화수목금토일])(?:요일|욜)"#) { match in
            guard let index = match.string(2).flatMap(weekdays.firstIndex(of:)) else { return nil }
            guard let week = match.string(1) else { return date(.weekday(index, .upcoming)) }
            return date(weeksAhead(week).map { .weekday(index, .weeksAhead($0)) } ?? .void)
        },
        // 다음주 화, 담주 월: 주를 적었으면 요일은 한 글자여도 된다.
        Rule(#"(?<![가-힣])("# + weekWords + #")\s?([월화수목금토일])(?![가-힣])"#) { match in
            guard let index = match.string(2).flatMap(weekdays.firstIndex(of:)),
                  let weeks = match.string(1).flatMap(weeksAhead) else { return nil }
            return date(.weekday(index, .weeksAhead(weeks)))
        },
        // fri, friday, next mon, this fri, last friday(지난 때)
        Rule(#"(?<![A-Za-z0-9])(?:(next|this|last)\s+)?("# + englishWeekdayPattern + #")(?![A-Za-z0-9])"#,
             caseInsensitive: true) { match in
            guard let word = match.string(2)?.lowercased(),
                  let index = englishWeekdays.firstIndex(of: String(word.prefix(3))) else { return nil }
            switch match.string(1)?.lowercased() {
            case "next": return date(.weekday(index, .weeksAhead(1)))
            case "this": return date(.weekday(index, .weeksAhead(0)))
            case "last": return date(.void)
            default:
                // sun, sat은 보통 낱말이기도 하다. 시각이나 범위와 함께 있을 때만 요일로 읽는다.
                return date(.weekday(index, .upcoming), requirement: ["sun", "sat"].contains(word) ? .needsCompany : .none)
            }
        },

        // 2026-11-20T15:00:00, 2026-11-20T15:00Z
        Rule(#"(?<![\d\-./A-Za-z])(\d{4})-(\d{1,2})-(\d{1,2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?"#
            + #"(Z|[+-]\d{2}:?\d{2})?(?![\d:])"#) { match in
            guard let spec = monthDay(match.int(2), match.int(3), year: match.int(1).map(DateSpec.Year.exact)),
                  let hour = match.int(4), let minute = match.int(5),
                  var time = timeSpec(hour: hour, minute: minute, leadingZero: true) else { return nil }
            time.zone = match.string(6)
            return piece(.dateTime(spec, time))
        },
        // 2026-11-20, 2026.11.20, 2026/11/20
        Rule(#"(?<![\d\-./A-Za-z])(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)(?![-/.]\d)"#) { match in
            monthDay(match.int(2), match.int(3), year: match.int(1).map(DateSpec.Year.exact)).map { date($0) }
        },
        // 2026. 11. 20.
        Rule(#"(?<![\d\-./A-Za-z])(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})(?!\d)(?!\.\d)\.?"#) { match in
            monthDay(match.int(2), match.int(3), year: match.int(1).map(DateSpec.Year.exact)).map { date($0) }
        },
        // 11월 20~22일
        Rule(#"(?<![\d.])(\d{1,2})월\s*(\d{1,2})\s*[~-]\s*(\d{1,2})일"# + notADay) { match in
            guard let first = monthDay(match.int(1), match.int(2)), let last = monthDay(match.int(1), match.int(3))
            else { return nil }
            return piece(.dateSpan(first, last))
        },
        // 11월 20일, 2026년 11월 20일, 내년 12월 1일
        Rule(#"(?<![\d.])(?:(\d{4})년\s*|(올해|금년|내년|내후년)\s*)?(\d{1,2})월\s*(\d{1,2})일"#) { match in
            var year = match.int(1).map(DateSpec.Year.exact)
            switch match.string(2) {
            case "올해", "금년": year = .fromNow(0)
            case "내년": year = .fromNow(1)
            case "내후년": year = .fromNow(2)
            default: break
            }
            return monthDay(match.int(3), match.int(4), year: year).map { date($0) }
        },
        // 다음 달 20일, 이번 달 15일
        Rule(#"(?<![가-힣])(이번|다음|담|다다음)\s?달\s*(\d{1,2})일"# + notADay) { match in
            guard let day = match.int(2), let word = match.string(1) else { return nil }
            let months = word == "이번" ? 0 : (word == "다다음" ? 2 : 1)
            return date(.monthOffsetDay(months: months, day: day))
        },
        // Nov 20, November 20th, Nov 20, 2026
        Rule(#"(?<![A-Za-z0-9])("# + monthPattern + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?![\d:A-Za-z/])"#
            + #"(?!\s*[aApP]\.?[mM]\b)(?:,?\s*(\d{4})(?![\d:A-Za-z/]))?"#, caseInsensitive: true) { match in
            monthDay(month(match.string(1)), match.int(2), year: match.int(3).map(DateSpec.Year.exact)).map { date($0) }
        },
        // 20 Nov, 20th November 2026. `3 may`는 보통 글과 가려지지 않아 읽지 않는다.
        Rule(#"(?<![A-Za-z0-9./:])(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthPattern + #")(?![A-Za-z0-9])"#
            + #"(?:,?\s*(\d{4})(?![\d:A-Za-z/]))?"#, caseInsensitive: true) { match in
            guard match.string(2)?.lowercased() != "may" else { return nil }
            return monthDay(month(match.string(2)), match.int(1), year: match.int(3).map(DateSpec.Year.exact))
                .map { date($0) }
        },
        // 11/20. 분수로 읽힐 말이 뒤따르면(1/2 완료, 1/4분기) 날짜가 아니다.
        Rule(#"(?<![\d/.A-Za-z])(\d{1,2})/(\d{1,2})(?![\d/])(?!\.\d)"# + notAFraction) { match in
            monthDay(match.int(1), match.int(2), loose: true).map { date($0) }
        },
        // 11.20. 소수와 가려지지 않아 시각이나 범위와 함께 있을 때만 날짜로 읽는다.
        Rule(#"(?<![\d/.A-Za-z])(\d{1,2})\.(\d{1,2})(?![\d/%])(?!\.\d)"# + notADecimal) { match in
            monthDay(match.int(1), match.int(2), loose: true).map { date($0, requirement: .needsCompany) }
        },
        // 20~22일. 이번 달의 남은 날일 때만 날짜다(`3~5일 출장`을 16일에 적으면 기간이다).
        Rule(#"(?<![\d./A-Za-z])(\d{1,2})\s*[~-]\s*(\d{1,2})일"# + notADay) { match in
            guard let first = match.int(1), let last = match.int(2), first < last, (1...31).contains(last)
            else { return nil }
            return piece(.dateSpan(.comingDayThisMonth(first), .comingDayThisMonth(last)))
        },
        // 20일
        Rule(#"(?<![\d./])(\d{1,2})일"# + notADay) { match in
            guard let day = match.int(1), (1...31).contains(day), !match.isPreceded(by: countBeforeDay),
                  day != 1 || !match.isFollowed(by: countAfterDay) else { return nil }
            return date(.dayOfMonth(day))
        },

        // 날 뒤에 덧붙인 요일: (금), (Fri)
        Rule(#"\(\s?(?:[월화수목금토일]|"# + englishWeekdayPattern + #")\s?\)"#, caseInsensitive: true) { _ in
            piece(.weekdayNote)
        },
        // 시각에 붙지 않은 때를 가리키는 말. `낮`과 `밤`은 다른 낱말의 머리이기도 해서(낮잠, 밤새) 낱말의 끝일 때만.
        Rule(#"(오전|오후|아침|점심|저녁|새벽|(?:낮|밤)(?=$|[^가-힣]|에|까지|부터|쯤))"#) { match in
            match.string(1).flatMap(DayPart.init(word:)).map { piece(.dayPart($0)) }
        },
        Rule(#"(?<![A-Za-z])(morning|afternoon|evening|night)(?![A-Za-z])"#, caseInsensitive: true) { match in
            match.string(1).flatMap(DayPart.init(word:)).map { piece(.dayPart($0)) }
        },
    ]
}
