/// `tokens.json`의 키를 타입으로 옮긴 것. rawValue가 JSON 키다.
/// 키를 추가하면 여기에 case를 더한다. 값은 코드에 적지 않는다.

public enum ColorToken: String, CaseIterable, Sendable {
    case surface
    case surface2 = "surface-2"
    case surface3 = "surface-3"
    case hover
    case text
    case text2 = "text-2"
    case text3 = "text-3"
    case line
    case outline
    case guide
    case accent
    case onAccent = "on-accent"
    case warn
    case highlight1Background = "hl-1-bg"
    case highlight1Foreground = "hl-1-fg"
    case highlight2Background = "hl-2-bg"
    case highlight2Foreground = "hl-2-fg"
    case highlight3Background = "hl-3-bg"
    case highlight3Foreground = "hl-3-fg"
    case highlight4Background = "hl-4-bg"
    case highlight4Foreground = "hl-4-fg"
    case codeBackground = "code-bg"
    case codeLine = "code-line"
    case codeForeground = "code-fg"
    case link
}

/// 형광펜 색. 번호는 저장 문법의 `==글자=={n}`과 같다(D-008). 1이 기본(노랑).
public enum HighlightColor: Int, CaseIterable, Sendable {
    case yellow = 1
    case gray = 2
    case rose = 3
    case blue = 4

    public var background: ColorToken { ColorToken(rawValue: "hl-\(rawValue)-bg")! }
    public var foreground: ColorToken { ColorToken(rawValue: "hl-\(rawValue)-fg")! }
}

public enum ShadowToken: String, CaseIterable, Sendable {
    case window = "shadow-window"
    case pop = "shadow-pop"
}

public enum FontRole: String, CaseIterable, Sendable {
    case display = "font-display"
    case h2 = "font-h2"
    case body = "font-body"
    case ui = "font-ui"
    case micro = "font-micro"
    case mono = "font-mono"
}

public enum SpaceToken: String, CaseIterable, Sendable {
    case sp1 = "sp-1"
    case sp2 = "sp-2"
    case sp3 = "sp-3"
    case sp4 = "sp-4"
    case sp5 = "sp-5"
    case sp6 = "sp-6"
}

public enum ShapeToken: String, CaseIterable, Sendable {
    case windowRadius = "r-window"
    case controlRadius = "r-control"
    case chipRadius = "r-chip"
    case checkRadius = "r-check"
    case highlightRadius = "r-hl"
    case borderWidth = "bw"
    case chromeHeight = "chrome-h"
    case codeRadius = "r-code"
    case codeBlockRadius = "r-codeblock"
}

/// 구성 요소 치수. `doc-pad`는 네 변 값이라 `ThemeTokens.docPadding`으로 따로 낸다.
public enum ComponentToken: String, CaseIterable, Sendable {
    case gutter
    case indent
    case checkSize = "check-size"
    case iconGap = "icon-gap"
    case pickGutter = "pick-gutter"
    case controlHeight = "ctl-h"
    case rowHeight = "row-h"
    case caretWidth = "caret-w"
    case iconButton = "icon-btn"
    case menubarIcon = "menubar-icon"
    case browseWidth = "browse-w"
    /// 노트 상단 줄: 요소 사이, 오른쪽 여백(spec 5.1).
    case chromeGap = "chrome-gap"
    case chromePaddingEnd = "chrome-pad-end"
    /// 선 아이콘 크기 세 단계(spec 18.2의 12, 13, 14pt).
    case iconSmall = "icon-s"
    case iconMedium = "icon-m"
    case iconLarge = "icon-l"
    /// 나란히 놓인 아이콘 버튼 사이(spec 5.3).
    case iconButtonGap = "icon-btn-gap"
    /// 노트 색 칸(spec 5.4): 크기, 사이, 고른 칸의 테두리 두께이자 띄우는 거리.
    case swatchSize = "swatch-size"
    case swatchGap = "swatch-gap"
    case swatchRing = "swatch-ring"
    case menuWidth = "menu-w"
    /// 노트 창 너비: 기본, 최소, 최대(spec 4.1, 임시 값).
    case noteWidth = "note-w"
    case noteWidthMin = "note-w-min"
    case noteWidthMax = "note-w-max"
}

/// 치수가 아니라 비율로 적는 구성 요소 값(`component` 구역, `%` 표기).
public enum RatioToken: String, CaseIterable, Sendable {
    /// 노트 창 높이 한도: 화면 높이에서 차지할 수 있는 몫(spec 5.6, 임시 값).
    case noteMaxScreenHeight = "note-h-max-screen"
}

/// 치수가 아니라 개수로 적는 구성 요소 값(`component` 구역, 단위 없는 정수).
public enum CountToken: String, CaseIterable, Sendable {
    /// 노트 창의 본문 영역이 적어도 보이는 본문 줄 수(D-031, 임시 값). 글이 그보다 적어도 창은 이만큼 높다.
    case noteBodyLinesMin = "note-body-lines-min"
}

/// `motion` 구역의 키. 값은 `MotionTokens`로 묶여 나온다.
public enum MotionToken: String, CaseIterable, Sendable {
    case duration = "dur"
    case ease
    /// 임박한 리마인더의 종(spec 15): 주기, 가만히 있는 앞부분의 몫, 차례로 기우는 각도 셋,
    /// 돌리는 축(위에서부터의 몫), 곡선.
    case bellPeriod = "bell-period"
    case bellRest = "bell-rest"
    case bellAngle1 = "bell-angle-1"
    case bellAngle2 = "bell-angle-2"
    case bellAngle3 = "bell-angle-3"
    case bellPivot = "bell-pivot"
    case bellEase = "bell-ease"
}
