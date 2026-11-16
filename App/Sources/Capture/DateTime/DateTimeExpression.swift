import Foundation

/// 글에서 알아들은 날짜와 시간 표현 하나.
nonisolated struct DateTimeExpression: Hashable, Sendable {
    /// 읽으면서 짐작한 것. 하나라도 있으면 다르게 읽힐 수 있는 표현이다.
    struct Assumptions: OptionSet, Hashable, Sendable {
        let rawValue: Int

        /// 오전·오후를 적지 않아 지금 시각과 흔한 쓰임으로 골랐다(`3시`).
        static let meridiem = Assumptions(rawValue: 1 << 0)
        /// 날만 적어 시각을 기본값(오전 9시)으로 두었다(`내일`, `11월 20일`).
        static let timeOfDay = Assumptions(rawValue: 1 << 1)
        /// 날짜가 아닐 수도 있는 꼴이다(`1/2`, `20일`).
        static let looseDate = Assumptions(rawValue: 1 << 2)
        /// 적은 그대로 읽으니 이미 지난 때다(`오늘 오전 9시`를 오후에 적음, 지난 해의 날짜).
        static let past = Assumptions(rawValue: 1 << 3)
    }

    /// 시작. 리마인더는 이 시각에 걸린다.
    let start: Date
    /// 범위로 적었을 때의 끝(`3시~5시`, `11/20~11/22`).
    let end: Date?
    /// 표현이 차지한 글자(UTF-16). 밑줄을 긋거나 글에서 뺄 때 쓴다.
    let range: NSRange
    let assumptions: Assumptions

    /// 다르게 읽힐 수 있는 표현인지.
    var isAmbiguous: Bool { !assumptions.isEmpty }
}
