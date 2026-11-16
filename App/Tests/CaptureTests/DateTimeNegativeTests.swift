import Foundation
import Testing
@testable import Capture

/// 리마인더가 되어서는 안 되는 글과, 읽되 알려 두는 것(되풀이, 시간대).
@Suite nonisolated struct DateTimeNegativeTests {
    private func parse(_ text: String, now: Date = ParseCase.morning) -> DateTimeExpression? {
        DateTimeParser.firstExpression(in: text, now: now, calendar: TestClock.calendar)
    }

    @Test(arguments: [
        // 지난 때를 가리키는 말.
        "어제 회의록 정리", "어제 3시 회의록 정리", "그저께 메일 답장", "3일 전 메일 답장", "3일 전 3시 회의",
        "지난주 금요일 회의록", "지난 금요일 회의록", "저번 주 월요일 3시", "last friday notes", "yesterday 3pm notes",
        "2 days ago", "작년 12월 1일 사진", "지난달 20일 영수증", "5분 전 도착", "3시간 전 메일",
        // 되풀이.
        "매주 금요일", "매주 금요일 3시 회의", "매달 20일 정산", "every friday standup", "매일 운동",
        // 시각처럼 보이는 낱말.
        "3시즌 정주행", "2시리즈 몰아보기", "3시 방향", "두 시 방향 확인", "24시 편의점", "24시간 영업", "한시적 운영",
        // 기간과 횟수.
        "2박 3일", "1박 2일 여행", "1일 1커밋", "1일 3회", "주 5일", "30일 챌린지", "7일 무료", "3일 연속", "D-3일",
        "3~5일 출장", "2~3일 걸림", "3-4일 소요",
        // 분수와 점수.
        "9/10", "1/4분기", "2/3 찬성", "4/5 완성", "별점 9/10",
        // 소수의 범위.
        "1.5~2.5배", "3.5-4.5점",
        // 비율과 장, 절.
        "16:10 모니터", "16:9 비율", "요한복음 3:16",
        // 날을 가리키는 말로 시작할 뿐인 낱말.
        "내일배움카드", "모레노", "회비 낼 사람",
        // 그 밖에 혼자서는 뜻이 없는 것.
        "at 10", "오늘 할 일", "저녁 약속", "tonight's dinner",
    ])
    func neverBecomesAReminder(text: String) {
        let found = parse(text)
        #expect(found == nil, "\(text): \(String(describing: found))")
    }

    /// 지난 때를 가리키는 말은 붙어 있는 것만 가져간다. 뒤에 따로 적은 표현은 읽는다.
    @Test func pastWordsOnlyTakeWhatIsAttached() {
        #expect(parse("어제 못한 운동 내일 7시")?.start == ParseCase.at(11, 17, 19))
    }

    /// `3~5일`은 이번 달의 남은 날일 때만 날짜다. 달을 적으면 언제나 날짜다.
    @Test func dayRangeIsADateOnlyWhenItIsStillAhead() {
        #expect(parse("3~5일 출장") == nil)
        let early = parse("3~5일 출장", now: ParseCase.at(11, 2, 10))
        #expect(early?.start == ParseCase.at(11, 3, 9))
        #expect(early?.end == ParseCase.at(11, 5, 9))
        #expect(parse("12월 3~5일 출장")?.start == ParseCase.at(12, 3, 9))
        // 기간을 뜻하는 말이 뒤따르면 남은 날이어도 읽지 않는다.
        #expect(parse("20~22일 걸림") == nil)
    }

    /// 분수로도 읽히는 `M/D`는 다가오는 그날이 가까울 때만 날짜다.
    @Test func slashDateFarAheadIsTreatedAsAFraction() {
        #expect(parse("9/10") == nil)
        #expect(parse("9/10", now: ParseCase.at(9, 1, 10))?.start == ParseCase.at(9, 10, 9))
        // 시각이나 범위가 함께 있으면 날짜다.
        #expect(parse("9/10 3시")?.start == ParseCase.at(9, 10, 15, year: 2027))
        // 어제 날짜를 일 년 뒤로 읽지 않는다.
        #expect(parse("11/15 회의", now: ParseCase.at(11, 16, 14)) == nil)
        // 해를 넘겨 가까운 날은 날짜다.
        #expect(parse("1/5 신년회", now: ParseCase.at(12, 30, 10))?.start == ParseCase.at(1, 5, 9, year: 2027))
    }

    /// `매일 9시`는 다가오는 9시 한 번으로 읽고 되풀이였다고 알린다. 되풀이를 걸어 주지는 않는다.
    @Test func dailyIsReadOnceAndFlagged() throws {
        let found = try #require(parse("매일 9시 스탠드업"))
        #expect(found.start == ParseCase.at(11, 17, 9))
        #expect(found.end == nil)
        #expect(found.assumptions.contains(.recurring))
        #expect((("매일 9시 스탠드업") as NSString).substring(with: found.range) == "매일 9시")
        let english = try #require(parse("every day 9am standup"))
        #expect(english.start == ParseCase.at(11, 17, 9))
        #expect(english.assumptions.contains(.recurring))
        #expect(try !#require(parse("9시 스탠드업")).assumptions.contains(.recurring))
    }

    /// 시간대 이름은 바꿔 읽지 않고, 달력의 시간대로 읽었다고 알린다.
    @Test func timeZoneSuffixIsFlaggedAndReadLocally() throws {
        let pst = try #require(parse("3pm PST call"))
        #expect(pst.start == ParseCase.at(11, 16, 15))
        #expect(pst.assumptions.contains(.unknownTimeZone))
        #expect(("3pm PST call" as NSString).substring(with: pst.range) == "3pm PST")
        let colon = try #require(parse("15:00 UTC 배포"))
        #expect(colon.start == ParseCase.at(11, 16, 15))
        #expect(colon.assumptions.contains(.unknownTimeZone))
        // 달력의 시간대와 같은 이름이면 알릴 것이 없다.
        #expect(try !#require(parse("3pm KST call")).assumptions.contains(.unknownTimeZone))
        #expect(try !#require(parse("3pm call")).assumptions.contains(.unknownTimeZone))
        let iso = try #require(parse("2026-11-20T15:00:00Z"))
        #expect(iso.start == ParseCase.at(11, 20, 15))
        #expect(iso.assumptions.contains(.unknownTimeZone))
        #expect(try !#require(parse("2026-11-20T15:00:00+09:00")).assumptions.contains(.unknownTimeZone))
    }

    /// 오전·오후를 적지 않은 시각은 언제나 짐작했다고 알린다. 적었으면 알리지 않는다.
    @Test(arguments: [
        ("3시", true), ("9시", true), ("12시", true), ("3:30", true), ("내일 3시", true), ("세 시", true),
        ("3-5시", true), ("next monday at 10", true),
        ("오후 3시", false), ("15:00", false), ("09:00", false), ("3pm", false), ("저녁 7시", false),
        ("7시 저녁에", false), ("정오", false), ("오후 2~4시", false), ("3~5pm", false),
    ])
    func bareHoursAreAlwaysFlagged(text: String, isGuess: Bool) throws {
        #expect(try #require(parse(text)).assumptions.contains(.meridiem) == isGuess, "\(text)")
    }
}
