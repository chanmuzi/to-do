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
}
