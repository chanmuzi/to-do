@testable import DateTime
import Foundation
import Testing
@testable import Capture

/// 검토에서 잘못 읽힌 것으로 나온 글들. 줄마다 기대하는 값을 적었다(정책은 spec 7a).
/// 기본 "지금"은 2026년 11월 16일 월요일 10:00(서울)이다.
@Suite nonisolated struct DateTimeFailureTableTests {
    private typealias Case = ParseCase
    private static func at(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        ParseCase.at(month, day, hour, minute, year: year)
    }

    private static let noon30 = at(11, 16, 12, 30)
    private static let afternoon1 = at(11, 16, 13)
    private static let afternoon4 = at(11, 16, 16)
    private static let friday = at(11, 20, 10)
    private static let sunday = at(11, 22, 10)
    private static let yearEnd = at(12, 31, 23, 30)

    /// 앞에 0을 붙인 `HH:mm`은 24시간제다. 오후로 바꿔 읽지 않는다.
    @Test(arguments: [
        Case.row("09:00 스탠드업", at(11, 17, 9), absent: [.past, .meridiem]),
        Case.row("08:30 회의", at(11, 17, 8, 30), absent: [.past, .meridiem]),
        Case.row("07:00 기상", at(11, 17, 7), absent: [.past, .meridiem]),
        Case.row("03:00 배포", at(11, 17, 3), absent: [.past, .meridiem]),
        Case.row("01:00", at(11, 17, 1), absent: [.past, .meridiem]),
        Case.row("내일 06:00 기상", at(11, 17, 6), absent: [.past, .meridiem]),
        Case.row("내일 05:30 출발", at(11, 17, 5, 30), absent: [.past, .meridiem]),
        Case.row("오늘 09:00", at(11, 16, 9), flags: .past, absent: .meridiem),
        Case.row("09:00~18:00", at(11, 16, 9), to: at(11, 16, 18), flags: .past, absent: .meridiem),
        Case.row("00:00 배포", at(11, 17, 0), absent: [.past, .meridiem]),
        Case.row("24:00 마감", at(11, 17, 0), absent: [.past, .meridiem]),
        Case.row("13:30 회의", at(11, 16, 13, 30), absent: [.past, .meridiem]),
    ])
    func leadingZeroClockIsTwentyFourHour(item: ParseCase) {
        item.check()
    }

    /// 서머타임으로 없는 시각(02:30)은 그 뒤의 첫 시각이다.
    @Test func daylightSavingGapMovesToTheNextValidTime() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(newYork.date(from: DateComponents(year: 2027, month: 3, day: day, hour: hour, minute: minute)))
        }
        let found = try #require(
            DateTimeParser.firstExpression(in: "3/14 02:30", now: try date(13, 22), calendar: newYork)
        )
        #expect(found.start == (try date(14, 3)))
        #expect(!found.assumptions.contains(.past))
    }

    /// 12시는 정오다. 자정으로 읽지 않는다.
    @Test(arguments: [
        Case.row("12시 회의", at(11, 17, 12), now: afternoon1, flags: .meridiem),
        Case.row("12시 반 회의", at(11, 17, 12, 30), now: afternoon1, flags: .meridiem),
        Case.row("12:30 점심약속", at(11, 17, 12, 30), now: afternoon1, flags: .meridiem),
        Case.row("12-1시 점심", at(11, 16, 12), to: at(11, 16, 13), now: noon30, flags: .past, absent: []),
        // 끝(13:00)까지 지났으면 내일의 같은 범위다.
        Case.row("12-1시", at(11, 17, 12), to: at(11, 17, 13), now: afternoon1),
        // 아직 진행 중인 범위는 오늘이고 시작이 지났다고 알린다.
        Case.row("12시~2시", at(11, 16, 12), to: at(11, 16, 14), now: afternoon1, flags: .past, absent: []),
        Case.row("오늘 12시", at(11, 16, 12), now: afternoon1, flags: .past, absent: []),
        Case.row("오늘 12시", at(11, 16, 12), now: afternoon4, flags: .past, absent: []),
    ])
    func twelveIsNoon(item: ParseCase) {
        item.check()
    }

    /// 8~11시는 오전이다. 지났다고 밤으로 바꿔 읽지 않고 내일 아침으로 읽는다.
    @Test(arguments: [
        Case.row("10시 회의", at(11, 17, 10), now: noon30, flags: .meridiem),
        Case.row("11시 전화", at(11, 17, 11), now: noon30, flags: .meridiem),
        Case.row("9시 스탠드업", at(11, 17, 9), flags: .meridiem),
        Case.row("9-6시 근무", at(11, 16, 9), to: at(11, 16, 18), flags: [.past, .meridiem], absent: []),
        Case.row("9:00-6:00", at(11, 16, 9), to: at(11, 16, 18), flags: [.past, .meridiem], absent: []),
        Case.row("9-6시 근무", at(11, 16, 9), to: at(11, 16, 18), now: at(11, 16, 8), flags: .meridiem),
        // `저녁`은 뒤의 말(저녁 예약)에 딸린 것이다. 시각을 밤으로 바꾸지 않는다.
        Case.one("11시 저녁 예약 전화", "11시", at(11, 16, 11), flags: .meridiem),
    ])
    func morningHoursStayInTheMorning(item: ParseCase) {
        item.check()
    }

    /// 날과 함께 때를 가리키는 말만 적으면 그 무렵의 기본 시각이다.
    @Test(arguments: [
        Case.one("내일 저녁 약속", "내일 저녁", at(11, 17, 19), flags: .timeOfDay),
        Case.one("내일 오후 회의", "내일 오후", at(11, 17, 14), flags: .timeOfDay),
        Case.one("내일 밤", "내일 밤", at(11, 17, 21), flags: .timeOfDay),
        Case.one("내일 점심 약속", "내일 점심", at(11, 17, 12), flags: .timeOfDay),
        Case.one("금요일 저녁 회식", "금요일 저녁", at(11, 20, 19), flags: .timeOfDay),
        Case.one("금요일 오후", "금요일 오후", at(11, 20, 14), flags: .timeOfDay),
        Case.one("내일 아침 운동", "내일 아침", at(11, 17, 8), flags: .timeOfDay),
        Case.one("내일 새벽 출발", "내일 새벽", at(11, 17, 5), flags: .timeOfDay),
        Case.one("내일 오전 회의", "내일 오전", at(11, 17, 9), flags: .timeOfDay),
        Case.one("오늘밤 배포", "오늘밤", at(11, 16, 21), flags: .timeOfDay),
        Case.one("오늘 저녁 약속", "오늘 저녁", at(11, 16, 19), flags: .timeOfDay),
        Case.one("tomorrow evening dinner", "tomorrow evening", at(11, 17, 19), flags: .timeOfDay),
        Case.one("tonight deploy", "tonight", at(11, 16, 21), flags: .timeOfDay),
        // 다른 낱말의 머리인 `낮`, `밤`은 때를 가리키는 말이 아니다.
        Case.one("내일 낮잠 자기", "내일", at(11, 17, 9)),
        Case.one("내일 밤새 작업", "내일", at(11, 17, 9)),
    ])
    func dayPartGivesTheDefaultTime(item: ParseCase) {
        item.check()
    }

    @Test func dayPartDefaultsLiveInOneTable() {
        #expect(DateTimeDefaults.dateOnlyHour == 9)
        #expect(DateTimeDefaults.dayPartHours == [
            .dawn: 5, .earlyMorning: 8, .morning: 9, .midday: 12, .afternoon: 14, .evening: 19, .night: 21,
        ])
    }

    /// 떨어뜨려 적은 날과 시각. 차지한 글자는 두 곳이다.
    @Test(arguments: [
        Case.split("내일 회의 3시", ["내일", "3시"], at(11, 17, 15)),
        Case.one("내일은 3시 회의", "내일은 3시", at(11, 17, 15)),
        Case.split("금요일 팀 회식 7시", ["금요일", "7시"], at(11, 20, 19)),
        Case.split("오늘 회의 3시", ["오늘", "3시"], at(11, 16, 15)),
        Case.split("내일 저녁 회식 7시", ["내일 저녁", "7시"], at(11, 17, 19)),
        Case.split("내일 워크숍 3-5시", ["내일", "3-5시"], at(11, 17, 15), to: at(11, 17, 17)),
        Case.split("3시 회의 내일", ["3시", "내일"], at(11, 17, 15)),
        // 소수와 가려지지 않는 `3.2`는 떨어진 시각만으로는 날짜가 되지 않는다.
        Case.one("버전 3.2 배포 3시", "3시", at(11, 16, 15)),
        // 다른 곳의 시각이 둘이면 어느 것인지 알 수 없다. 합치지 않는다.
        Case.one("내일 회의 3시, 통화 5시", "내일", at(11, 17, 9)),
        // 제 날을 가진 시각은 떨어진 날과 합치지 않는다.
        Case.one("내일 회의, 모레 3시 발표", "내일", at(11, 17, 9)),
    ])
    func separatedDateAndTimeJoin(item: ParseCase) {
        item.check()
    }

    /// 날과 시각 사이의 요일 덧말과 이음말.
    @Test(arguments: [
        Case.one("11/20(금) 3시", "11/20(금) 3시", at(11, 20, 15)),
        Case.one("11/20(금) 15:00", "11/20(금) 15:00", at(11, 20, 15)),
        Case.one("11월 20일(금) 오후 3시", "11월 20일(금) 오후 3시", at(11, 20, 15)),
        Case.one("20일(금) 3시", "20일(금) 3시", at(11, 20, 15)),
        Case.one("11/20 금요일 3시", "11/20 금요일 3시", at(11, 20, 15)),
        Case.one("11/20 (금) 발표", "11/20 (금)", at(11, 20, 9)),
        Case.one("tomorrow at 3pm", "tomorrow at 3pm", at(11, 17, 15)),
        Case.one("friday at 3pm", "friday at 3pm", at(11, 20, 15)),
        Case.one("next monday at 10", "next monday at 10", at(11, 23, 10)),
        Case.one("friday @ 3", "friday @ 3", at(11, 20, 15)),
        Case.one("내일에 3시", "내일에 3시", at(11, 17, 15)),
        Case.one("내일, 3시", "내일, 3시", at(11, 17, 15)),
    ])
    func connectivesBetweenDateAndTime(item: ParseCase) {
        item.check()
    }

    /// 시각이 날보다 앞에 와도 한 표현이다.
    @Test(arguments: [
        Case.one("3pm tomorrow", "3pm tomorrow", at(11, 17, 15)),
        Case.one("at 3pm tomorrow", "3pm tomorrow", at(11, 17, 15)),
        Case.one("3 p.m. tomorrow", "3 p.m. tomorrow", at(11, 17, 15)),
        Case.one("noon tomorrow", "noon tomorrow", at(11, 17, 12)),
        Case.one("10am friday", "10am friday", at(11, 20, 10)),
        Case.one("3시 금요일", "3시 금요일", at(11, 20, 15)),
        Case.one("3시 내일", "3시 내일", at(11, 17, 15)),
        Case.one("3시에 내일", "3시에 내일", at(11, 17, 15)),
        Case.one("3pm on friday", "3pm on friday", at(11, 20, 15)),
        Case.one("8pm tonight", "8pm tonight", at(11, 16, 20)),
        // 날이 제 시각을 따로 달고 있으면 앞의 시각과 잇지 않는다.
        Case.one("3시, 내일 5시", "3시", at(11, 16, 15)),
    ])
    func timeBeforeDate(item: ParseCase) {
        item.check()
    }

    @Test(arguments: [
        Case.one("Nov 20 3pm", "Nov 20 3pm", at(11, 20, 15)),
        Case.one("November 20th standup", "November 20th", at(11, 20, 9)),
        Case.one("20 Nov 3pm", "20 Nov 3pm", at(11, 20, 15)),
        Case.one("Dec 25, 2027 party", "Dec 25, 2027", at(12, 25, 9, year: 2027)),
        Case.one("2026. 11. 20. 3시", "2026. 11. 20. 3시", at(11, 20, 15)),
        Case.one("2026.11.20 3시", "2026.11.20 3시", at(11, 20, 15)),
        Case.one("2026-11-20T15:00:00", "2026-11-20T15:00:00", at(11, 20, 15), absent: .meridiem),
        Case.one("2026-11-20T15:00 리뷰", "2026-11-20T15:00", at(11, 20, 15)),
    ])
    func monthNamesAndWrittenDates(item: ParseCase) {
        item.check()
    }

    /// 줄여 쓴 말과 달, 해를 건너는 말.
    @Test(arguments: [
        Case.one("내일 모레 발표", "내일 모레", at(11, 18, 9)),
        Case.one("내일모레 발표", "내일모레", at(11, 18, 9)),
        Case.one("낼 3시 회의", "낼 3시", at(11, 17, 15)),
        Case.one("수욜 3시", "수욜 3시", at(11, 18, 15)),
        Case.one("금욜 회식", "금욜", at(11, 20, 9)),
        Case.one("다음주 화 2시", "다음주 화 2시", at(11, 24, 14)),
        Case.one("담주 월 10시", "담주 월 10시", at(11, 23, 10)),
        Case.one("담주 금요일", "담주 금요일", at(11, 27, 9)),
        Case.one("차주 금요일", "차주 금요일", at(11, 27, 9)),
        Case.one("다음 달 20일", "다음 달 20일", at(12, 20, 9)),
        Case.one("다음달 20일 3시", "다음달 20일 3시", at(12, 20, 15)),
        Case.one("이번 달 15일", "이번 달 15일", at(11, 15, 9), flags: .past),
        Case.one("내년 12월 1일", "내년 12월 1일", at(12, 1, 9, year: 2027)),
        Case.one("올해 12월 1일", "올해 12월 1일", at(12, 1, 9)),
    ])
    func colloquialAndRelativeMonthForms(item: ParseCase) {
        item.check()
    }

    /// 오늘을 가리키는 날은 언제나 오늘이다. 다음 주, 다음 달, 다음 해로 넘기지 않고 지났으면 지났다고 알린다.
    @Test(arguments: [
        Case.one("11/16 발표", "11/16", at(11, 16, 9), flags: .past),
        Case.one("11월 16일 발표", "11월 16일", at(11, 16, 9), flags: .past),
        Case.one("16일 마감", "16일", at(11, 16, 9), flags: .past),
        Case.one("16일 3시 마감", "16일 3시", at(11, 16, 15), absent: .past),
        Case.one("월요일 9시", "월요일 9시", at(11, 16, 9), flags: .past),
        Case.one("금요일 데모", "금요일", at(11, 20, 9), now: friday, flags: .past),
        Case.one("fri", "fri", at(11, 20, 9), now: friday, flags: .past),
        Case.one("일요일", "일요일", at(11, 22, 9), now: sunday, flags: .past),
        Case.one("sunday", "sunday", at(11, 22, 9), now: sunday, flags: .past),
        Case.one("12월 31일", "12월 31일", at(12, 31, 9), now: yearEnd, flags: .past),
        Case.one("12/31 송년회", "12/31", at(12, 31, 9), now: yearEnd, flags: .past),
        // 아직 9시 전이면 지난 때가 아니다.
        Case.one("16일 마감", "16일", at(11, 16, 9), now: at(11, 16, 8), absent: .past),
    ])
    func todayNeverRollsForward(item: ParseCase) {
        item.check()
    }

    /// 범위의 양 끝이 제 날을 가지면 저마다 제 날로 읽는다.
    @Test(arguments: [
        Case.one("내일 10시~내일 12시", "내일 10시~내일 12시", at(11, 17, 10), to: at(11, 17, 12)),
        Case.one("내일 3시 ~ 모레 3시", "내일 3시 ~ 모레 3시", at(11, 17, 15), to: at(11, 18, 15)),
        Case.one("20~22일 출장", "20~22일", at(11, 20, 9), to: at(11, 22, 9)),
        Case.one("11월 20~22일 출장", "11월 20~22일", at(11, 20, 9), to: at(11, 22, 9)),
        Case.one("12월 3~5일 출장", "12월 3~5일", at(12, 3, 9), to: at(12, 5, 9)),
        Case.one("금요일~월요일 휴가", "금요일~월요일", at(11, 20, 9), to: at(11, 23, 9)),
        Case.one("3~5pm", "3~5pm", at(11, 16, 15), to: at(11, 16, 17), now: afternoon4, flags: .past),
        Case.one("9시~오후 5시", "9시~오후 5시", at(11, 16, 9), to: at(11, 16, 17), flags: .past),
    ])
    func rangesWithTheirOwnDates(item: ParseCase) {
        item.check()
    }

    /// 범위의 양 끝은 서로 맞게 읽는다: 오전·오후는 양쪽으로 이어지고, 같은 날에 뒤로 읽을 길이 없을 때만 다음 날이다.
    @Test(arguments: [
        Case.one("9-6시", "9-6시", at(11, 17, 9), to: at(11, 17, 18), now: at(11, 16, 19)),
        Case.one("12-1시", "12-1시", at(11, 16, 12), to: at(11, 16, 13)),
        Case.one("12시~2시", "12시~2시", at(11, 16, 12), to: at(11, 16, 14)),
        Case.one("09:00~18:00", "09:00~18:00", at(11, 17, 9), to: at(11, 17, 18), now: at(11, 16, 19)),
        Case.one("오후 2~4시", "오후 2~4시", at(11, 16, 14), to: at(11, 16, 16), absent: .meridiem),
        Case.one("11시~1시", "11시~1시", at(11, 16, 11), to: at(11, 16, 13)),
        Case.one("2-4pm", "2-4pm", at(11, 16, 14), to: at(11, 16, 16), absent: .meridiem),
        Case.one("2pm-4", "2pm-4", at(11, 16, 14), to: at(11, 16, 16), absent: .meridiem),
        Case.one("2pm-4 sync", "2pm-4", at(11, 16, 14), to: at(11, 16, 16)),
        Case.one("14~16시", "14~16시", at(11, 16, 14), to: at(11, 16, 16), absent: .meridiem),
        Case.one("10시~12시", "10시~12시", at(11, 16, 10), to: at(11, 16, 12), flags: .past),
        Case.one("밤 11시~1시", "밤 11시~1시", at(11, 16, 23), to: at(11, 17, 1)),
        Case.one("오후 11시~새벽 2시", "오후 11시~새벽 2시", at(11, 16, 23), to: at(11, 17, 2)),
        Case.one("11/20~11/22", "11/20~11/22", at(11, 20, 9), to: at(11, 22, 9)),
    ])
    func rangesAreInternallyConsistent(item: ParseCase) {
        item.check()
    }

    /// `반`은 뒤에 한글이 이어지지 않을 때만 30분이다. `N시 M분 전`은 뺀다.
    @Test(arguments: [
        Case.one("3시 반납하기", "3시", at(11, 16, 15)),
        Case.one("5시 반찬 사기", "5시", at(11, 16, 17)),
        Case.one("2시 반장 회의", "2시", at(11, 16, 14)),
        Case.one("3시 반 회의", "3시 반", at(11, 16, 15, 30)),
        Case.one("3시 반에 회의", "3시 반", at(11, 16, 15, 30)),
        Case.one("3시 반", "3시 반", at(11, 16, 15, 30)),
        Case.one("3시 5분 전 도착", "3시 5분 전", at(11, 16, 14, 55)),
        Case.one("3시 15분 전", "3시 15분 전", at(11, 16, 14, 45)),
        Case.one("3시 30분 전화하기", "3시 30분", at(11, 16, 15, 30)),
        Case.one("B1-3시 회의", "3시", at(11, 16, 15)),
    ])
    func halfAndMinutesBefore(item: ParseCase) {
        item.check()
    }

    /// 전각 숫자와 풀어 쓴 한글(NFD)도 읽고, 차지한 글자는 받은 글 그대로의 자리다.
    @Test func fullWidthAndDecomposedInputKeepOriginalOffsets() throws {
        let fullWidth = "내일 ３시 회의"
        let wide = try #require(DateTimeParser.firstExpression(
            in: fullWidth, now: ParseCase.morning, calendar: TestClock.calendar
        ))
        #expect(wide.start == Self.at(11, 17, 15))
        #expect((fullWidth as NSString).substring(with: wide.range) == "내일 ３시")

        let decomposedDay = "내일".decomposedStringWithCanonicalMapping
        #expect(decomposedDay.utf16.count == 5)
        let text = "회의 " + decomposedDay + " 3시 준비"
        let found = try #require(DateTimeParser.firstExpression(
            in: text, now: ParseCase.morning, calendar: TestClock.calendar
        ))
        #expect(found.start == Self.at(11, 17, 15))
        #expect(found.ranges == [NSRange(location: 3, length: 8)])
        #expect((text as NSString).substring(with: found.range) == decomposedDay + " 3시")

        // 전각 쌍점과 물결표.
        let wideRange = try #require(DateTimeParser.firstExpression(
            in: "１５：００～１６：３０", now: ParseCase.morning, calendar: TestClock.calendar
        ))
        #expect(wideRange.start == Self.at(11, 16, 15))
        #expect(wideRange.end == Self.at(11, 16, 16, 30))
        #expect(wideRange.ranges == [NSRange(location: 0, length: 11)])
    }

    /// 지금부터 얼마 뒤와 한글로 적은 수.
    @Test(arguments: [
        Case.one("in an hour and a half", "in an hour and a half", at(11, 16, 11, 30)),
        Case.one("in 1.5 hours", "in 1.5 hours", at(11, 16, 11, 30)),
        Case.one("in half an hour", "in half an hour", at(11, 16, 10, 30)),
        Case.one("1시간 반 후", "1시간 반 후", at(11, 16, 11, 30)),
        Case.one("1.5시간 뒤", "1.5시간 뒤", at(11, 16, 11, 30)),
        Case.one("한 시간 뒤", "한 시간 뒤", at(11, 16, 11)),
        Case.one("두시간 후", "두시간 후", at(11, 16, 12)),
        Case.one("한 시간 반 뒤 통화", "한 시간 반 뒤", at(11, 16, 11, 30)),
        Case.one("일주일 뒤", "일주일 뒤", at(11, 23, 9)),
        Case.one("한달 뒤", "한달 뒤", at(12, 16, 9)),
        Case.one("두 달 후 점검", "두 달 후", at(1, 16, 9, year: 2027)),
        Case.one("3개월 뒤", "3개월 뒤", at(2, 16, 9, year: 2027)),
        Case.one("이틀 뒤 3시", "이틀 뒤 3시", at(11, 18, 15)),
        Case.one("2주 뒤 금요일 3시", "2주 뒤 금요일 3시", at(12, 4, 15)),
        Case.one("오후 세시", "오후 세시", at(11, 16, 15), absent: .meridiem),
        Case.one("세 시 회의", "세 시", at(11, 16, 15), flags: .meridiem),
        Case.one("두시 반", "두시 반", at(11, 16, 14, 30)),
        Case.one("열두시 점심", "열두시", at(11, 16, 12)),
        Case.one("내일 아홉시", "내일 아홉시", at(11, 17, 9)),
    ])
    func durationsAndKoreanNumerals(item: ParseCase) {
        item.check()
    }
}
