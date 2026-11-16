import Foundation

/// 시각을 찾는 무늬.
///
/// 때를 가리키는 말(`오전`, `저녁` …)이 시각에 붙는 것은 두 경우뿐이다(spec 7a):
/// 시각 바로 앞에 있을 때(`저녁 7시`, 사이 공백은 있어도 된다)와 시각 바로 뒤에 `에`를 달고 있을 때(`7시 저녁에`).
/// `11시 저녁 예약 전화`의 `저녁`은 뒤의 말에 딸린 것이라 시각을 바꾸지 않는다.
nonisolated extension DateTimeLexer {
    /// 시 뒤에 붙으면 시각이 아닌 말: `3시간`, `3시즌`, `3시리즈`, `3시 방향`.
    private static let notAnHour = #"(?!간|즌|리즈|절|스템|\s*방향)"#
    /// `반`은 뒤에 한글이 이어지지 않거나 조사가 올 때만 30분이다(`3시 반납하기`, `5시 반찬`은 아니다).
    private static let half = #"\s*(반)(?=$|[^가-힣]|에|쯤|까지|부터|경)"#
    /// `3시 5분 전`의 `전`.
    private static let before = #"(?:\s*(전)(?=$|[^가-힣]|에|까지))?"#
    /// 시각 뒤에 `에`를 달고 따라오는 때를 가리키는 말. 글자로는 차지하지 않는다.
    private static let trailingPart = #"(?=(?:\s*("# + dayParts + #")에)?)"#
    /// 시각 뒤의 시간대 이름. 대문자로 적었을 때만.
    private static let zone = #"(?:\s*(PST|PDT|EST|EDT|CST|CDT|MST|MDT|HST|AKST|AKDT|UTC|GMT|KST|JST|CET|CEST|BST|IST|AEST|AEDT)"#
        + #"(?![A-Za-z]))?"#
    /// 화면 비율로 읽힐 말이 뒤따르면 시각이 아니다(`16:10 모니터`).
    private static let notARatio = #"(?!\s*(?:모니터|비율|화면|해상도|디스플레이|패널|스크린))"#
    /// 장과 절로 읽힐 말이 앞에 있으면 시각이 아니다(`요한복음 3:16`).
    private static let chapterBefore = regex(
        #"(?:복음|전서|후서|창세기|출애굽기|레위기|민수기|신명기|시편|잠언|전도서|로마서|계시록|사도행전"#
            + #"|John|Matthew|Mark|Luke|Genesis|Psalms?|Romans|Acts)\s?$"#
    )

    private static func time(
        hour: Int, minute: Int = 0, part: String? = nil, leadingZero: Bool = false, allows24: Bool = false,
        minutesBefore: Int = 0, zone: String? = nil, requirement: DateTimePiece.Requirement = .none
    ) -> DateTimePiece? {
        let dayPart = part.flatMap(DayPart.init(word:))
        guard var spec = timeSpec(
            hour: hour, minute: minute, part: dayPart, leadingZero: leadingZero, allows24: allows24
        ) else { return nil }
        spec.minutesBefore = minutesBefore
        spec.zone = zone
        return piece(.time(spec), requirement: requirement)
    }

    /// `N시`, `N시 M분`, `N시 반`, `N시 M분 전`. 모둠: 1 앞의 때, 2 시, 3 분, 4 전, 5 반, 6 뒤의 때.
    private static func hourPiece(_ match: Match, hour: Int?) -> DateTimePiece? {
        guard let hour, hour != 24 else { return nil }
        let minutes = match.has(5) ? 30 : (match.int(3) ?? 0)
        let isBefore = match.has(4)
        return time(
            hour: hour, minute: isBefore ? 0 : minutes, part: match.string(1) ?? match.string(6),
            minutesBefore: isBefore ? minutes : 0
        )
    }

    static let timeRules: [Rule] = [
        // 3시, 오후 3시, 10시 반, 3시 30분, PM 3시, 7시 저녁에, 3시 5분 전
        Rule(#"(?:("# + dayParts + #"|AM|PM)\s*)?(?<![\d.:])(\d{1,2})시"# + notAnHour
            + #"(?:\s*(\d{1,2})분"# + before + "|" + half + ")?" + trailingPart) { match in
            hourPiece(match, hour: match.int(2))
        },
        // 세시, 오후 세 시, 두시 반, 열두시
        Rule(#"(?:("# + dayParts + #")\s*|(?<![가-힣]))("# + KoreanNumeral.hourPattern + #")\s?시"# + notAnHour
            + #"(?=$|[^가-힣]|에|쯤|까지|부터|경|반|정각)(?:\s*(\d{1,2})분"# + before + "|" + half + ")?"
            + trailingPart) { match in
            hourPiece(match, hour: match.string(2).flatMap(KoreanNumeral.hour))
        },
        // 15:00, 09:00, 오후 3:30, 3:30 PM, PM 3:30, 15:00:00, 3:00 PM PST
        Rule(#"(?:("# + dayParts + #"|AM|PM)\s*)?(?<![\d.:])(\d{1,2}):(\d{2})(?::\d{2})?(?![\d:])"#
            + #"(?:\s*([aApP])\.?[mM]\.?(?![A-Za-z]))?"# + zone + notARatio) { match in
            guard let digits = match.string(2), let hour = Int(digits), let minute = match.int(3),
                  !match.isPreceded(by: chapterBefore) else { return nil }
            return time(
                hour: hour, minute: minute, part: match.string(4) ?? match.string(1),
                leadingZero: digits.count == 2 && digits.hasPrefix("0"), allows24: true, zone: match.string(5)
            )
        },
        // 3pm, 3 PM, 10 a.m., 3pm PST
        Rule(#"(?<![\d.:A-Za-z])(\d{1,2})\s*([aApP])\.?[mM]\.?(?![A-Za-z])"# + zone) { match in
            guard let hour = match.int(1), (1...12).contains(hour) else { return nil }
            return time(hour: hour, part: match.string(2), zone: match.string(3))
        },
        // PM 3 (대문자일 때만: "I am 3"을 읽지 않는다)
        Rule(#"(?<![A-Za-z0-9])(AM|PM)\s*(\d{1,2})(?![\d:시.])"#) { match in
            guard let hour = match.int(2), (1...12).contains(hour) else { return nil }
            return time(hour: hour, part: match.string(1))
        },
        // 3 o'clock
        Rule(#"(?<![\d.:A-Za-z])(\d{1,2})\s*o'?clock(?![A-Za-z])"#, caseInsensitive: true) { match in
            guard let hour = match.int(1), (1...12).contains(hour) else { return nil }
            return time(hour: hour)
        },
        // at 10, @ 3: 날과 함께 있을 때만 시각이다(`next monday at 10`).
        Rule(#"(?<![A-Za-z0-9])(?:at|@)\s*(\d{1,2})(?![\d:.,/%~A-Za-z가-힣-])(?!\s*(?:[aApP]\.?[mM]\b|시|분|o'?clock))"#,
             caseInsensitive: true) { match in
            guard let hour = match.int(1), (1...23).contains(hour) else { return nil }
            return time(hour: hour, requirement: .needsDate)
        },
        Rule(#"(?<![가-힣A-Za-z0-9])(정오|자정)"# + wordEnd) { match in
            time(hour: 12, part: match.string(1) == "정오" ? "오후" : "밤")
        },
        Rule(#"(?<![A-Za-z0-9])(noon|midnight)(?![A-Za-z0-9])"#, caseInsensitive: true) { match in
            time(hour: 12, part: match.string(1)?.lowercased() == "noon" ? "오후" : "밤")
        },
    ]
}
