import AppKit

/// 앱 메뉴의 뿌리. 글자로 맞는 항목이 없을 때 키 자리(가상 키 코드)로 한 번 더 찾는다.
///
/// AppKit은 메뉴 항목의 단축키를 이벤트의 글자로 견준다. 한글 입력 소스에서도 ⌘과 함께 누른 키는 보통 라틴
/// 글자로 오지만, 글자가 다르게 실려 오는 경우(다른 자판 배열, 자모가 실린 이벤트)에도 단축키 표에 적힌
/// 자리의 키가 듣게 한다(`ShortcutKey`는 키 자리로 적는다). 글자로 맞는 항목이 있으면 그것이 먼저다.
nonisolated final class KeyCodeMenu: NSMenu {
    /// 메뉴에서는 흐리지만 키 요청은 기록하는 미연결 명령(D-024).
    var reservedKeys: [Int: @MainActor () -> Void] = [:]

    /// 단축키 항목에 적어 두는 표시: 키 자리와 보조 키. 0은 "없음"이므로 1을 더해 둔다.
    static func tag(for chord: KeyChord) -> Int {
        (Int(chord.key.keyCode) + 1) << 8 | chord.modifiers.rawValue
    }

    // 이 SDK의 `NSMenu`와 `NSMenuItem`은 격리 없이 선언돼 있어 이 타입도 격리를 두지 않는다. AppKit은 메인에서 부른다.
    override init(title: String) {
        super.init(title: title)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let wanted = (Int(event.keyCode) + 1) << 8 | ShortcutModifiers(eventFlags: event.modifierFlags).rawValue
        if let record = reservedKeys[wanted] {
            MainActor.assumeIsolated { record() }
            return true
        }
        if super.performKeyEquivalent(with: event) { return true }
        guard let (menu, index) = Self.find(tag: wanted, in: self) else { return false }
        menu.update()
        guard menu.items[index].isEnabled else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    private static func find(tag: Int, in menu: NSMenu) -> (NSMenu, Int)? {
        for (index, item) in menu.items.enumerated() {
            if item.tag == tag, (!item.isHidden || item.allowsKeyEquivalentWhenHidden), item.action != nil {
                return (menu, index)
            }
            if let found = item.submenu.flatMap({ find(tag: tag, in: $0) }) { return found }
        }
        return nil
    }
}
