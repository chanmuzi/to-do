/// 편집 단축키(spec 13의 "편집" 표). 자판 배열과 입력 소스(한글)에 상관없이 같게 동작하도록
/// 글자가 아니라 키 자리(가상 키 코드)로 견준다.
nonisolated enum EditorShortcuts {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1)
        static let shift = Modifiers(rawValue: 2)
        static let option = Modifiers(rawValue: 4)
        static let control = Modifiers(rawValue: 8)
    }

    enum Key {
        static let one: UInt16 = 18
        static let two: UInt16 = 19
        static let three: UInt16 = 20
        static let nine: UInt16 = 25
        static let b: UInt16 = 11
        static let c: UInt16 = 8
        static let e: UInt16 = 14
        static let h: UInt16 = 4
        static let l: UInt16 = 37
        static let x: UInt16 = 7
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let returnKey: UInt16 = 36
        static let up: UInt16 = 126
        static let down: UInt16 = 125
    }

    /// Tab, ⇧Tab은 여기 없다(글자 입력 경로에서 처리한다).
    static func action(keyCode: UInt16, modifiers: Modifiers) -> EditorAction? {
        switch (modifiers, keyCode) {
        case ([.command, .shift], Key.nine): .toggleTodo
        case ([.command], Key.returnKey): .toggleDone
        case ([.command, .control], Key.up): .moveLineUp
        case ([.command, .control], Key.down): .moveLineDown
        case ([.command, .option], Key.leftBracket): .fold
        case ([.command, .option], Key.rightBracket): .unfold
        case ([.command, .option], Key.one): .heading(1)
        case ([.command, .option], Key.two): .heading(2)
        case ([.command, .option], Key.three): .heading(3)
        case ([.command], Key.b): .bold
        case ([.command, .shift], Key.x): .strikethrough
        case ([.command, .shift], Key.h): .highlight
        case ([.command], Key.e): .inlineCode
        case ([.command, .option], Key.c): .codeBlock
        case ([.command], Key.l): .link
        default: nil
        }
    }
}
