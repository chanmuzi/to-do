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
    /// 인라인 코드 바탕, 코드 블록 바탕. 테두리는 없다(D-035).
    case codeBackground = "code-bg"
    case codeBlockBackground = "codeblock-bg"
    /// 코드 글자(코드 블록, 그리고 인라인 코드를 "plain"으로 골랐을 때).
    case codeForeground = "code-fg"
    /// 인라인 코드 글자의 강조색("accent", 기본). 규칙 1의 예외다(D-035).
    case codeAccent = "code-accent"
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
    /// 인용문(spec 6): 왼쪽 막대의 너비, 블록 왼쪽 끝에서 글자까지의 거리.
    case quoteBarWidth = "quote-bar-w"
    case quotePadding = "quote-pad"
    /// 인라인 코드 상자(spec 6): 좌우 안쪽 여백, 바깥 간격, 높이, 줄 가운데에서 아래로 내리는 양,
    /// 글자 기준선을 올리는 양.
    case codePaddingX = "code-pad-x"
    case codeGap = "code-gap"
    case codeHeight = "code-h"
    case codeDrop = "code-drop"
    case codeRise = "code-rise"
    /// 코드 블록(spec 6): 좌우와 위아래 안쪽 여백, 위아래 바깥 간격.
    case codeBlockPaddingX = "codeblock-pad-x"
    case codeBlockPaddingY = "codeblock-pad-y"
    case codeBlockGap = "codeblock-gap"
    /// 링크 주소를 적는 칸의 너비(spec 6).
    case linkFieldWidth = "link-field-w"
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
    /// 빠른 캡처 바(spec 7): 너비, 높이, 좌우 여백, 요소 사이, 오른쪽 표시(스페이스, 리마인더) 앞의 덧간격,
    /// 나타날 때 아래에서 올라오는 거리(사라질 때는 그만큼 내려간다).
    case captureWidth = "capture-w"
    case captureHeight = "capture-h"
    case capturePadding = "capture-pad"
    case captureGap = "capture-gap"
    case captureValueGap = "capture-val-gap"
    case captureRise = "capture-rise"
    /// 노트 찾기(spec 8): 안쪽 여백, 모서리, 검색 칸 높이와 그 아래 틈, 줄 안의 요소 사이,
    /// 노트 상단 줄과의 틈, 노트 오른쪽 끝에서 들여 놓는 거리.
    case browsePadding = "browse-pad"
    case browseRadius = "browse-r"
    case browseFindHeight = "browse-find-h"
    case browseFindGap = "browse-find-gap"
    case browseGap = "browse-gap"
    case browseAnchorGap = "browse-anchor-gap"
    case browseAnchorInset = "browse-anchor-inset"
}

/// 치수가 아니라 비율로 적는 구성 요소 값(`component` 구역, `%` 표기).
public enum RatioToken: String, CaseIterable, Sendable {
    /// 노트 창 높이 한도: 화면 높이에서 차지할 수 있는 몫(spec 5.6, 임시 값).
    case noteMaxScreenHeight = "note-h-max-screen"
    /// 캡처 바가 뜨는 높이: 화면(메뉴 막대와 Dock을 뺀 영역) 아래 끝에서 바 아래쪽까지의 몫(spec 4.1 "화면 가운데 아래쪽", 임시 값).
    case captureBottomScreen = "capture-bottom-screen"
    /// 앵커 없이 여는 노트 찾기가 뜨는 높이: 화면 위 끝에서 목록 위쪽까지의 몫(임시 값). 목록이 아래로 자라므로 위쪽에 둔다.
    case browseTopScreen = "browse-top-screen"
    /// 노트 찾기 높이 한도: 화면 높이에서 차지할 수 있는 몫(임시 값). 넘으면 목록이 스크롤된다.
    case browseMaxScreenHeight = "browse-h-max-screen"
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
    /// 입력 커서가 켜져 있는 시간이자 꺼져 있는 시간(`TextCaret`).
    case caretBlink = "caret-blink"
}
