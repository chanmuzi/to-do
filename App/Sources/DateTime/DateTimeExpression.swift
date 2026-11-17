import Foundation

/// 글에서 알아들은 날짜와 시간 표현 하나.
public nonisolated struct DateTimeExpression: Hashable, Sendable {
    /// 읽으면서 짐작했거나 알려 둘 것. 하나라도 있으면 다르게 읽힐 수 있는 표현이다.
    public struct Assumptions: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// 오전·오후를 적지 않아 흔한 쓰임으로 골랐다(`3시`는 오후, `9시`는 오전).
        public static let meridiem = Assumptions(rawValue: 1 << 0)
        /// 날만 적어 시각을 기본값으로 두었다(`내일`은 오전 9시, `내일 저녁`은 오후 7시).
        public static let timeOfDay = Assumptions(rawValue: 1 << 1)
        /// 날짜가 아닐 수도 있는 꼴이다(`1/2`, `20일`).
        public static let looseDate = Assumptions(rawValue: 1 << 2)
        /// 적은 그대로 읽으니 이미 지난 때다(`오늘 09:00`을 10시에 적음, 오늘 날짜만 적었는데 9시가 지남).
        /// 범위는 시작이 지났으면 붙는다. 리마인더로 걸지 않는다.
        public static let past = Assumptions(rawValue: 1 << 3)
        /// 되풀이를 뜻하는 말이 붙어 있었다(`매일 9시`). 되풀이는 지원하지 않고 다가오는 한 번만 읽었다.
        public static let recurring = Assumptions(rawValue: 1 << 4)
        /// 달력과 다른 시간대가 적혀 있었다(`3pm PST`). 시간대를 바꾸지 않고 달력의 시간대로 읽었다.
        public static let unknownTimeZone = Assumptions(rawValue: 1 << 5)
    }

    /// 시작. 리마인더는 이 시각에 걸린다.
    public let start: Date
    /// 범위로 적었을 때의 끝(`3시~5시`, `11/20~11/22`).
    public let end: Date?
    /// 표현이 차지한 글자(받은 글 그대로의 UTF-16 자리). 앞에서부터 차례로, 서로 겹치지 않는다.
    /// 날과 시각을 떨어뜨려 적으면 둘이다(`내일 회의 3시`의 `내일`과 `3시`).
    public let ranges: [NSRange]
    public let assumptions: Assumptions
    public var isDateOnly: Bool = false

    /// 첫 조각의 처음부터 마지막 조각의 끝까지.
    public var range: NSRange {
        ranges.dropFirst().reduce(ranges.first ?? NSRange(location: 0, length: 0), NSUnionRange)
    }

    /// 다르게 읽힐 수 있는 표현인지.
    public var isAmbiguous: Bool { !assumptions.isEmpty }
}
