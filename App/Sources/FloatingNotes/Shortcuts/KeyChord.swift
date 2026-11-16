import AppKit

/// 단축키에 쓰는 키. 자판 배열과 입력 소스(한글)에 상관없이 같게 동작하도록 키 자리(가상 키 코드)로 적는다.
///
/// 듣는 곳마다 견주는 방식:
/// - 전역 단축키(`CarbonHotKeyRegistrar`)와 편집기(`EditorShortcuts`)는 키 자리(`keyCode`)로 견준다.
/// - 앱 메뉴(`MainMenu`)의 항목은 AppKit이 글자(`menuKeyEquivalent`)로 견준다. 글자가 맞지 않으면
///   (`KeyCodeMenu`) 키 자리로 한 번 더 찾으므로, 이벤트에 한글 자모가 실려 와도 같은 자리의 키가 듣는다.
nonisolated enum ShortcutKey: String, Hashable, Sendable, CaseIterable {
    case a, b, c, e, f, h, k, l, m, n, p, q, r, t, v, w, x, z
    case one, two, three, nine
    case comma, slash, backtick, leftBracket, rightBracket
    case returnKey, tab, space, escape, up, down

    /// 가상 키 코드(ANSI 자판의 자리).
    var keyCode: UInt16 {
        switch self {
        case .a: 0
        case .b: 11
        case .c: 8
        case .e: 14
        case .f: 3
        case .h: 4
        case .k: 40
        case .l: 37
        case .m: 46
        case .n: 45
        case .p: 35
        case .q: 12
        case .r: 15
        case .t: 17
        case .v: 9
        case .w: 13
        case .x: 7
        case .z: 6
        case .one: 18
        case .two: 19
        case .three: 20
        case .nine: 25
        case .comma: 43
        case .slash: 44
        case .backtick: 50
        case .leftBracket: 33
        case .rightBracket: 30
        case .returnKey: 36
        case .tab: 48
        case .space: 49
        case .escape: 53
        case .up: 126
        case .down: 125
        }
    }

    /// 단축키 표에 적는 이름(`tokens.json`의 `shortcuts`와 같은 표기).
    var label: String {
        switch self {
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .nine: "9"
        case .comma: ","
        case .slash: "/"
        case .backtick: "`"
        case .leftBracket: "["
        case .rightBracket: "]"
        case .returnKey: "↵"
        case .tab: "⇥"
        case .space: "Space"
        case .escape: "esc"
        case .up: "↑"
        case .down: "↓"
        default: rawValue.uppercased()
        }
    }

    /// `NSMenuItem.keyEquivalent`에 넣는 글자.
    var menuKeyEquivalent: String {
        switch self {
        case .returnKey: "\r"
        case .tab: "\t"
        case .space: " "
        case .escape: "\u{1B}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        case .one, .two, .three, .nine, .comma, .slash, .backtick, .leftBracket, .rightBracket: label
        default: rawValue
        }
    }
}

/// 보조 키. 표에 적는 차례(⌃ ⌥ ⇧ ⌘)는 macOS의 관례와 같다.
nonisolated struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = ShortcutModifiers(rawValue: 1)
    static let option = ShortcutModifiers(rawValue: 2)
    static let shift = ShortcutModifiers(rawValue: 4)
    static let command = ShortcutModifiers(rawValue: 8)

    private static let displayOrder: [(ShortcutModifiers, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    var labels: [String] {
        Self.displayOrder.filter { contains($0.0) }.map(\.1)
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}

/// 키 하나와 보조 키의 조합.
nonisolated struct KeyChord: Hashable, Sendable {
    var key: ShortcutKey
    var modifiers: ShortcutModifiers

    init(_ key: ShortcutKey, _ modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 표에 적는 모습. 예: `["⇧", "⌘", "T"]`.
    var labels: [String] { modifiers.labels + [key.label] }
}
