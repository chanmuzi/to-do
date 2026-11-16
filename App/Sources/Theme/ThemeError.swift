import Foundation

public enum ThemeError: Error, Equatable, CustomStringConvertible {
    /// 번들에서 `tokens.json`이나 글꼴 폴더를 찾지 못했다.
    case resourceNotFound(String)
    /// JSON 구조가 예상과 다르다.
    case malformedDocument(String)
    /// 코드가 쓰는 토큰이 문서에 없다.
    case missingToken(String)
    /// 토큰 값을 해석하지 못했다.
    case invalidValue(key: String, value: String)
    /// 덮어쓰려는 키가 `tokens.json`에 없다.
    case unknownOverrideKey(String)
    /// 글꼴 등록 실패.
    case fontRegistrationFailed(file: String, reason: String)

    public var description: String {
        switch self {
        case .resourceNotFound(let name): "리소스를 찾지 못했습니다: \(name)"
        case .malformedDocument(let detail): "tokens.json 구조가 올바르지 않습니다: \(detail)"
        case .missingToken(let key): "토큰이 없습니다: \(key)"
        case .invalidValue(let key, let value): "토큰 값을 해석하지 못했습니다: \(key) = \(value)"
        case .unknownOverrideKey(let key): "덮어쓸 수 없는 키입니다: \(key)"
        case .fontRegistrationFailed(let file, let reason): "글꼴을 등록하지 못했습니다: \(file) (\(reason))"
        }
    }
}
