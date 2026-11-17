/// 고유어와 한자어로 적은 수.
nonisolated enum KoreanNumeral {
    /// 시를 세는 말. 긴 것부터 적는다(무늬에서 `열한`이 `열`보다 먼저 맞게).
    static let hourPattern = "열한|열두|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열"
    private static let hours = [
        "한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10,
        "열한": 11, "열두": 12,
    ]
    /// 주와 달을 세는 말(`일주일`, `이주`, `한 달`, `두 달`).
    static let countPattern = "한|두|세|네|일|이|삼|사"
    private static let counts = ["한": 1, "두": 2, "세": 3, "네": 4, "일": 1, "이": 2, "삼": 3, "사": 4]
    static let dayPattern = "하루|이틀|사흘|나흘"
    private static let days = ["하루": 1, "이틀": 2, "사흘": 3, "나흘": 4]

    static func hour(_ word: String) -> Int? { hours[word] }
    static func count(_ word: String) -> Int? { counts[word] }
    static func days(_ word: String) -> Int? { days[word] }
}
