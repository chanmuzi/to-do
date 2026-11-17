@testable import DateTime
import Foundation
import Testing
@testable import Capture

/// 날짜와 시간 표현 읽기. 달력은 서울 시간이고, "지금"은 경우마다 준다.
/// 기본 "지금"은 2026년 11월 16일 월요일 10:00이다.
@Suite nonisolated struct DateTimeParserTests {
    typealias Case = ParseCase

    private static func at(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        ParseCase.at(month, day, hour, minute, year: year)
    }

    /// 월요일 오전 10시.
    private static let morning = ParseCase.morning
    /// 같은 날 밤 10시.
    private static let night = at(11, 16, 22)
    /// 11월의 마지막 날(월요일) 오전 10시.
    private static let monthEnd = at(11, 30, 10)
    /// 한 해의 마지막 날(목요일) 밤 11시 30분.
    private static let yearEnd = at(12, 31, 23, 30)

    private static func one(
        _ text: String, _ match: String, _ start: Date, to end: Date? = nil, now: Date = morning
    ) -> Case {
        ParseCase.one(text, match, start, to: end, now: now)
    }

    private func parse(_ text: String, now: Date = DateTimeParserTests.morning) -> DateTimeExpression? {
        DateTimeParser.firstExpression(in: text, now: now, calendar: TestClock.calendar)
    }

    private func check(_ item: Case) {
        item.check()
    }

    // MARK: - 시각

    @Test(arguments: [
        one("오후 3시 회의", "오후 3시", at(11, 16, 15)),
        one("오전 10시 반 스탠드업", "오전 10시 반", at(11, 16, 10, 30)),
        one("3시 30분 치과", "3시 30분", at(11, 16, 15, 30)),
        one("3시반 치과", "3시반", at(11, 16, 15, 30)),
        one("15:00 배포", "15:00", at(11, 16, 15)),
        one("3pm call", "3pm", at(11, 16, 15)),
        one("call at 3 PM", "3 PM", at(11, 16, 15)),
        one("call at 3:30 PM", "3:30 PM", at(11, 16, 15, 30)),
        one("PM 3 미팅", "PM 3", at(11, 16, 15)),
        one("PM 3:30 미팅", "PM 3:30", at(11, 16, 15, 30)),
        one("오후 3:30 미팅", "오후 3:30", at(11, 16, 15, 30)),
        one("저녁 7시 약속", "저녁 7시", at(11, 16, 19)),
        one("아침 9시 운동", "아침 9시", at(11, 17, 9)),
        one("밤 11시 마감", "밤 11시", at(11, 16, 23)),
        one("낮 2시 산책", "낮 2시", at(11, 16, 14)),
        one("새벽 2시 배포", "새벽 2시", at(11, 17, 2)),
        one("정오 점심", "정오", at(11, 16, 12)),
        one("자정 배포", "자정", at(11, 17, 0)),
        one("noon lunch", "noon", at(11, 16, 12)),
        one("deploy at midnight", "midnight", at(11, 17, 0)),
        one("10:30 회의", "10:30", at(11, 16, 10, 30)),
        one("약 3시쯤 도착", "3시", at(11, 16, 15)),
    ])
    func clockTimes(item: Case) {
        check(item)
    }

    /// 오전, 오후를 적지 않은 시각은 흔한 쪽으로 읽는다(1~7시는 오후, 8~11시는 오전, 12시는 정오).
    /// 그 시각이 오늘 지났으면 같은 시각의 내일이다. 오전과 오후를 바꿔 읽지 않는다.
    @Test(arguments: [
        one("3시 회의", "3시", at(11, 16, 15)),
        one("3시 회의", "3시", at(11, 17, 15), now: night),
        one("9시 회의", "9시", at(11, 17, 9)),
        one("9시 회의", "9시", at(11, 17, 9), now: night),
        one("11시 회의", "11시", at(11, 16, 11)),
        one("11시 회의", "11시", at(11, 17, 11), now: night),
        one("7시 회의", "7시", at(11, 16, 19), now: at(11, 16, 6)),
        one("7시 회의", "7시", at(11, 17, 19), now: night),
        one("6시 운동", "6시", at(11, 16, 18)),
        one("6시 운동", "6시", at(11, 17, 18), now: night),
        one("8시 출근", "8시", at(11, 16, 8), now: at(11, 16, 7)),
        one("12시 점심", "12시", at(11, 16, 12)),
        one("9:15 회의", "9:15", at(11, 17, 9, 15)),
        one("3:30 회의", "3:30", at(11, 16, 15, 30)),
        // 시각 뒤의 때를 가리키는 말은 `에`가 붙었을 때만 시각의 것이다.
        one("7시 저녁 약속", "7시", at(11, 16, 19)),
        one("9시 아침 회의", "9시", at(11, 17, 9)),
        one("9시 저녁에 통화", "9시", at(11, 16, 21)),
        one("11시 밤에 배포", "11시", at(11, 16, 23)),
        // 밤늦게 적은 새벽 시각은 다가오는 그 시각이다.
        one("밤 1시 취침", "밤 1시", at(11, 17, 1), now: night),
    ])
    func bareHoursFollowTheContext(item: Case) {
        check(item)
    }

    /// 12시의 오전과 오후.
    @Test(arguments: [
        one("12am", "12am", at(11, 17, 0)),
        one("12pm", "12pm", at(11, 16, 12)),
        one("12:30 am", "12:30 am", at(11, 17, 0, 30)),
        one("12:30 PM", "12:30 PM", at(11, 16, 12, 30)),
        one("오전 12시", "오전 12시", at(11, 17, 0)),
        one("오후 12시", "오후 12시", at(11, 16, 12)),
        one("오후 12시 30분", "오후 12시 30분", at(11, 16, 12, 30)),
        one("밤 12시", "밤 12시", at(11, 17, 0)),
        one("내일 밤 12시", "내일 밤 12시", at(11, 18, 0)),
        one("내일 오전 12시", "내일 오전 12시", at(11, 17, 0)),
        one("내일 12시", "내일 12시", at(11, 17, 12)),
    ])
    func twelveOClock(item: Case) {
        check(item)
    }

    // MARK: - 날

    @Test(arguments: [
        one("내일 회의 준비", "내일", at(11, 17, 9)),
        one("내일 오전 10시 스탠드업", "내일 오전 10시", at(11, 17, 10)),
        one("내일 3시 회의", "내일 3시", at(11, 17, 15)),
        one("내일 9시 회의", "내일 9시", at(11, 17, 9)),
        one("모레 오후 1시 점심", "모레 오후 1시", at(11, 18, 13)),
        one("글피 10시", "글피 10시", at(11, 19, 10)),
        one("오늘 저녁 7시", "오늘 저녁 7시", at(11, 16, 19)),
        one("tomorrow 3pm sync", "tomorrow 3pm", at(11, 17, 15)),
        one("today 5pm", "today 5pm", at(11, 16, 17)),
        one("내일 3pm 미팅", "내일 3pm", at(11, 17, 15)),
        one("금요일 3시 데모", "금요일 3시", at(11, 20, 15)),
        one("금요일 데모", "금요일", at(11, 20, 9)),
        // 오늘이 월요일이다. 요일만 적어도 오늘이다(9시가 지났어도 다음 주로 넘기지 않는다).
        one("월요일 주간회의", "월요일", at(11, 16, 9)),
        one("월요일 5시 회고", "월요일 5시", at(11, 16, 17)),
        one("이번 주 금요일 2시", "이번 주 금요일 2시", at(11, 20, 14)),
        one("다음 주 월요일 9시", "다음 주 월요일 9시", at(11, 23, 9)),
        one("다음주 수요일 리뷰", "다음주 수요일", at(11, 25, 9)),
        one("fri 3pm demo", "fri 3pm", at(11, 20, 15)),
        one("friday standup", "friday", at(11, 20, 9)),
        one("this fri", "this fri", at(11, 20, 9)),
        one("next mon 10am", "next mon 10am", at(11, 23, 10)),
        one("next mon 오전 10시", "next mon 오전 10시", at(11, 23, 10)),
        one("11/20 발표", "11/20", at(11, 20, 9)),
        one("11/20 3시 발표", "11/20 3시", at(11, 20, 15)),
        one("11.20 3시 발표", "11.20 3시", at(11, 20, 15)),
        one("11월 20일 오전 9시 발표", "11월 20일 오전 9시", at(11, 20, 9)),
        one("11월 20일 발표", "11월 20일", at(11, 20, 9)),
        one("20일 마감", "20일", at(11, 20, 9)),
        one("20일까지 제출", "20일", at(11, 20, 9)),
        one("2026-11-20 14:00 리뷰", "2026-11-20 14:00", at(11, 20, 14)),
        one("2026-11-20 발표", "2026-11-20", at(11, 20, 9)),
        one("2027년 3월 2일 개학", "2027년 3월 2일", at(3, 2, 9, year: 2027)),
        one("3일 뒤 10시 점검", "3일 뒤 10시", at(11, 19, 10)),
        one("2주 후 회의", "2주 후", at(11, 30, 9)),
        one("in 3 days", "in 3 days", at(11, 19, 9)),
    ])
    func dates(item: Case) {
        check(item)
    }

    @Test(arguments: [
        one("30분 뒤 스트레칭", "30분 뒤", at(11, 16, 10, 30)),
        one("2시간 후 확인", "2시간 후", at(11, 16, 12)),
        one("2시간 후에 확인", "2시간 후", at(11, 16, 12)),
        one("1시간 반 뒤 통화", "1시간 반 뒤", at(11, 16, 11, 30)),
        one("1시간 20분 뒤 통화", "1시간 20분 뒤", at(11, 16, 11, 20)),
        one("in 2 hours", "in 2 hours", at(11, 16, 12)),
        one("in 30 min", "in 30 min", at(11, 16, 10, 30)),
        one("ping in an hour", "in an hour", at(11, 16, 11)),
    ])
    func fromNow(item: Case) {
        check(item)
    }

    // MARK: - 범위

    @Test(arguments: [
        one("3시~5시 회의", "3시~5시", at(11, 16, 15), to: at(11, 16, 17)),
        one("3-5시 워크숍", "3-5시", at(11, 16, 15), to: at(11, 16, 17)),
        one("15:00-16:30 인터뷰", "15:00-16:30", at(11, 16, 15), to: at(11, 16, 16, 30)),
        one("오후 2시 ~ 4시 세미나", "오후 2시 ~ 4시", at(11, 16, 14), to: at(11, 16, 16)),
        // 앞에 붙은 오전, 오후는 끝까지 이어진다.
        one("오후 2~4시 세미나", "오후 2~4시", at(11, 16, 14), to: at(11, 16, 16)),
        one("2시부터 4시까지 집중", "2시부터 4시까지", at(11, 16, 14), to: at(11, 16, 16)),
        // 정오를 넘는 범위.
        one("11시~1시 점심", "11시~1시", at(11, 16, 11), to: at(11, 16, 13)),
        one("오전 11시~1시", "오전 11시~1시", at(11, 16, 11), to: at(11, 16, 13)),
        // 자정을 넘는 범위.
        one("밤 11시~1시 배포", "밤 11시~1시", at(11, 16, 23), to: at(11, 17, 1)),
        // 끝에만 붙은 오전, 오후는 시작으로 거슬러 간다.
        one("3~5pm workshop", "3~5pm", at(11, 16, 15), to: at(11, 16, 17)),
        one("11~1pm lunch", "11~1pm", at(11, 16, 11), to: at(11, 16, 13)),
        one("3pm to 5pm", "3pm to 5pm", at(11, 16, 15), to: at(11, 16, 17)),
        one("내일 3-5시 워크숍", "내일 3-5시", at(11, 17, 15), to: at(11, 17, 17)),
        one("내일 오후 2~4시", "내일 오후 2~4시", at(11, 17, 14), to: at(11, 17, 16)),
        one("금요일 10시~12시 면접", "금요일 10시~12시", at(11, 20, 10), to: at(11, 20, 12)),
        one("11/20~11/22 출장", "11/20~11/22", at(11, 20, 9), to: at(11, 22, 9)),
        one("11.20~11.22 출장", "11.20~11.22", at(11, 20, 9), to: at(11, 22, 9)),
        one("11월 20일~11월 22일 출장", "11월 20일~11월 22일", at(11, 20, 9), to: at(11, 22, 9)),
        one("12/30~1/2 휴가", "12/30~1/2", at(12, 30, 9), to: at(1, 2, 9, year: 2027)),
    ])
    func ranges(item: Case) {
        check(item)
    }

    // MARK: - 달과 해를 넘길 때

    @Test(arguments: [
        one("내일 9시", "내일 9시", at(12, 1, 9), now: monthEnd),
        one("3일 뒤", "3일 뒤", at(12, 3, 9), now: monthEnd),
        // 11월에는 31일이 없다.
        one("31일 마감", "31일", at(12, 31, 9), now: monthEnd),
        one("5일 마감", "5일", at(12, 5, 9), now: monthEnd),
        one("1/5 10시", "1/5 10시", at(1, 5, 10, year: 2027), now: monthEnd),
        one("1월 5일", "1월 5일", at(1, 5, 9, year: 2027), now: monthEnd),
        one("내일 오전 9시", "내일 오전 9시", at(1, 1, 9, year: 2027), now: yearEnd),
        one("밤 12시", "밤 12시", at(1, 1, 0, year: 2027), now: yearEnd),
        one("1시간 뒤", "1시간 뒤", at(1, 1, 0, 30, year: 2027), now: yearEnd),
        one("금요일", "금요일", at(1, 1, 9, year: 2027), now: yearEnd),
        one("3일 마감", "3일", at(1, 3, 9, year: 2027), now: yearEnd),
        // 2월 29일은 다음 윤년.
        one("2월 29일", "2월 29일", at(2, 29, 9, year: 2028)),
        // 오늘 날짜를 적었으면 시각이 지났어도 오늘이다(내년으로 넘기지 않는다).
        one("11월 16일 오전 9시", "11월 16일 오전 9시", at(11, 16, 9)),
        one("11월 16일 오후 3시", "11월 16일 오후 3시", at(11, 16, 15)),
    ])
    func rollover(item: Case) {
        check(item)
    }

    // MARK: - 읽지 않는 글

    @Test(arguments: [
        "PR #482 리뷰",
        "3-5개 사기",
        "v2.3.1 배포",
        "1/2 완료",
        "밀가루 1/2 컵",
        "10시간 걸림",
        "3시간 반 걸리는 작업",
        "010-1234-5678 전화",
        "02-123-4567",
        "3",
        "우유 3개",
        "오늘 할 일",
        "today's plan",
        "버전 2.30",
        "1.5배 빠르게",
        "20일간 휴가",
        "3일째 야근",
        "2일 전 메일 답장",
        "수정오류 확인",
        "I am 3 years old",
        "sat down with the team",
        "the sun is out",
        "5분 대기",
        "16:9 비율",
        "2월 30일 9시",
        "25시 편의점",
        "오전 15시",
        "13월 2일",
        "점수 3:2로 승리",
        "우유 사기",
        "",
    ])
    func ordinaryTextIsNotRead(text: String) {
        let found = parse(text)
        #expect(found == nil, "\(text): \(String(describing: found))")
    }

    // MARK: - 짐작한 것

    @Test func assumptionsSayWhatWasGuessed() throws {
        #expect(try #require(parse("오후 3시 회의")).assumptions == [])
        #expect(try #require(parse("15:00 배포")).isAmbiguous == false)
        #expect(try #require(parse("3시 회의")).assumptions == .meridiem)
        #expect(try #require(parse("내일 회의")).assumptions == .timeOfDay)
        #expect(try #require(parse("내일 오전 10시")).assumptions == [])
        #expect(try #require(parse("11/20 발표")).assumptions == [.looseDate, .timeOfDay])
        #expect(try #require(parse("20일 3시")).assumptions == [.looseDate, .meridiem])
        #expect(try #require(parse("3시~5시")).assumptions == .meridiem)
        #expect(try #require(parse("오후 2~4시")).assumptions == [])
        #expect(try #require(parse("30분 뒤")).assumptions == [])
    }

    /// 지난 때로 읽히는 것은 날을 분명히 적었을 때뿐이고, 그렇게 읽었다고 알려 준다.
    @Test func explicitPastIsKeptAndFlagged() throws {
        let earlierToday = try #require(parse("오늘 오전 9시 회의"))
        #expect(earlierToday.start == Self.at(11, 16, 9))
        #expect(earlierToday.assumptions.contains(.past))

        let oldDate = try #require(parse("2020-01-01 정리"))
        #expect(oldDate.start == Self.at(1, 1, 9, year: 2020))
        #expect(oldDate.assumptions.contains(.past))

        // 날을 적지 않았거나 해를 적지 않은 지난 날은 지난 때로 읽지 않고 다가오는 것으로 읽는다.
        for text in ["9시", "오전 9시", "11/5 회의", "15일", "일요일", "정오"] {
            let found = try #require(parse(text, now: Self.at(11, 16, 14)), "\(text)")
            #expect(found.start > Self.at(11, 16, 14), "\(text)")
            #expect(!found.assumptions.contains(.past), "\(text)")
        }
    }

    @Test func theFirstExpressionWins() {
        #expect(parse("30분 뒤 전화하고 내일 10시 회의")?.start == Self.at(11, 16, 10, 30))
        #expect(parse("내일 10시 회의, 30분 뒤 전화")?.start == Self.at(11, 17, 10))
    }

    /// 시간대는 달력에서 온다.
    @Test func timeZoneComesFromTheCalendar() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 서울의 10:00은 UTC로 01:00이다. 같은 순간에 "3시"는 UTC 달력에서 그날 15:00(UTC)이다.
        let found = try #require(DateTimeParser.firstExpression(in: "3시", now: Self.morning, calendar: utc))
        #expect(found.start == Self.morning.addingTimeInterval(14 * 3600))
    }
}
