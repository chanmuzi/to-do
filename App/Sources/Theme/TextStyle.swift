import CoreGraphics

/// 글자 역할(spec 3.1의 표 한 줄씩). 어떤 토큰을 묶는지만 정하고 값은 `tokens.json`에서 온다.
public enum TextStyle: String, CaseIterable, Sendable {
    case librarySection, libraryListHeading, scheduleTitle
    case sectionLabel, scheduleInput, scheduleTime
    case title      // 노트 제목(상단 줄)
    case h1, h2, h3 // 본문 제목
    case body
    case strong     // 본문 굵게
    case paneTitle  // 라이브러리 목록 제목
    case selected
    case row        // 라이브러리 줄 제목
    case rowSub     // 라이브러리 줄 미리 보기
    case ui         // 정보(시간, 개수)
    case uiStrong   // 임박한 리마인더(spec 5.2)
    case micro      // 날짜, 보조 숫자
    case code       // 인라인 코드
    case codeBlock  // 코드 블록
    case capture    // 캡처 입력

    struct Keys {
        let font: FontRole
        let size: String
        let lineHeight: String
        let weight: String
        var tracking: String? = nil
    }

    var keys: Keys {
        switch self {
        case .librarySection: Keys(font: .body, size: "fs-library-section", lineHeight: "lh-micro", weight: "fw-selected")
        case .libraryListHeading: Keys(font: .body, size: "fs-list-heading", lineHeight: "lh-list-heading", weight: "fw-title")
        case .scheduleTitle: Keys(font: .body, size: "fs-schedule-title", lineHeight: "lh-body", weight: "fw-title")
        case .sectionLabel: Keys(font: .body, size: "fs-micro", lineHeight: "lh-micro", weight: "fw-ui-strong")
        case .scheduleInput: Keys(font: .body, size: "fs-capture", lineHeight: "lh-body", weight: "fw-title")
        case .scheduleTime: Keys(font: .ui, size: "fs-schedule-time", lineHeight: "lh-ui", weight: "fw-ui")
        case .title: Keys(font: .body, size: "fs-title", lineHeight: "lh-ui", weight: "fw-title")
        case .h1: Keys(font: .display, size: "fs-h1", lineHeight: "lh-h1", weight: "fw-h1", tracking: "ls-h1")
        case .h2: Keys(font: .h2, size: "fs-h2", lineHeight: "lh-h2", weight: "fw-h2", tracking: "ls-h2")
        case .h3: Keys(font: .body, size: "fs-h3", lineHeight: "lh-h3", weight: "fw-h3")
        case .body: Keys(font: .body, size: "fs-body", lineHeight: "lh-body", weight: "fw-body")
        case .strong: Keys(font: .body, size: "fs-body", lineHeight: "lh-body", weight: "fw-strong")
        case .paneTitle: Keys(font: .body, size: "fs-pane-title", lineHeight: "lh-body", weight: "fw-title")
        case .selected: Keys(font: .body, size: "fs-body", lineHeight: "lh-body", weight: "fw-selected")
        case .row: Keys(font: .body, size: "fs-row", lineHeight: "lh-row", weight: "fw-row")
        case .rowSub: Keys(font: .body, size: "fs-row-sub", lineHeight: "lh-ui", weight: "fw-body")
        case .ui: Keys(font: .ui, size: "fs-ui", lineHeight: "lh-ui", weight: "fw-ui")
        case .uiStrong: Keys(font: .ui, size: "fs-ui", lineHeight: "lh-ui", weight: "fw-ui-strong")
        case .micro: Keys(font: .micro, size: "fs-micro", lineHeight: "lh-micro", weight: "fw-ui")
        case .code: Keys(font: .mono, size: "fs-code", lineHeight: "lh-body", weight: "fw-body")
        case .codeBlock: Keys(font: .mono, size: "fs-code", lineHeight: "lh-code", weight: "fw-body")
        case .capture: Keys(font: .body, size: "fs-capture", lineHeight: "lh-body", weight: "fw-body")
        }
    }
}

/// 글자 역할 하나의 풀린 값.
public struct TextStyleSpec: Hashable, Sendable {
    /// 글꼴 이름 후보. 앞에서부터 쓸 수 있는 첫 글꼴을 쓴다.
    public let families: [String]
    public let size: CGFloat
    public let lineHeight: CGFloat
    /// CSS 굵기(400, 650 등).
    public let weight: CGFloat
    /// 자간(pt). 토큰이 없으면 0.
    public let tracking: CGFloat
}
