import AppKit

/// 편집 단축키(spec 13의 "편집" 표). 자판 배열과 입력 소스(한글)에 상관없이 같게 동작하도록
/// 글자가 아니라 키 자리(가상 키 코드)로 견준다.
nonisolated package enum EditorShortcuts {
    typealias Modifiers = NSEvent.ModifierFlags

    enum Key {
        static let one: UInt16 = 18
        static let two: UInt16 = 19
        static let three: UInt16 = 20
        static let nine: UInt16 = 25
        static let b: UInt16 = 11
        static let c: UInt16 = 8
        static let d: UInt16 = 2
        static let e: UInt16 = 14
        static let v: UInt16 = 9
        static let u: UInt16 = 32
        static let h: UInt16 = 4
        static let l: UInt16 = 37
        static let x: UInt16 = 7
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let returnKey: UInt16 = 36
        static let up: UInt16 = 126
        static let down: UInt16 = 125
    }

    /// 키 하나와 그 동작.
    struct Binding: Hashable, Sendable {
        let modifiers: Modifiers
        let keyCode: UInt16
        let action: EditorAction

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
            hasher.combine(action)
        }
    }

    /// 편집기가 `performKeyEquivalent`에서 받는 키 전부. Tab, ⇧Tab은 여기 없다(글자 입력 경로에서 처리한다).
    /// 단축키 표(App의 `ShortcutTable`의 "편집" 줄)와 같아야 하고, App의 테스트가 둘을 견준다.
    static let bindings: [Binding] = [
        Binding(modifiers: [.command, .shift], keyCode: Key.nine, action: .toggleTodo),
        Binding(modifiers: [.command], keyCode: Key.returnKey, action: .toggleDone),
        Binding(modifiers: [.command, .control], keyCode: Key.up, action: .moveLineUp),
        Binding(modifiers: [.command, .control], keyCode: Key.down, action: .moveLineDown),
        Binding(modifiers: [.command, .option], keyCode: Key.leftBracket, action: .fold),
        Binding(modifiers: [.command, .option], keyCode: Key.rightBracket, action: .unfold),
        Binding(modifiers: [.command, .option], keyCode: Key.one, action: .heading(1)),
        Binding(modifiers: [.command, .option], keyCode: Key.two, action: .heading(2)),
        Binding(modifiers: [.command, .option], keyCode: Key.three, action: .heading(3)),
        Binding(modifiers: [.command], keyCode: Key.d, action: .duplicate),
        Binding(modifiers: [.command, .option], keyCode: Key.v, action: .pasteInside),
        Binding(modifiers: [.command], keyCode: Key.u, action: .underline),
        Binding(modifiers: [.command], keyCode: Key.b, action: .bold),
        Binding(modifiers: [.command, .shift], keyCode: Key.x, action: .strikethrough),
        Binding(modifiers: [.command, .shift], keyCode: Key.h, action: .highlight),
        Binding(modifiers: [.command], keyCode: Key.e, action: .inlineCode),
        Binding(modifiers: [.command, .option], keyCode: Key.c, action: .codeBlock),
        Binding(modifiers: [.command], keyCode: Key.l, action: .link),
    ]

    package static func binding(for action: EditorAction) -> (keyCode: UInt16, flags: NSEvent.ModifierFlags)? {
        bindings.first { $0.action == action }.map { ($0.keyCode, $0.modifiers) }
    }

    static func action(keyCode: UInt16, modifiers: Modifiers) -> EditorAction? {
        bindings.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.action
    }
}
