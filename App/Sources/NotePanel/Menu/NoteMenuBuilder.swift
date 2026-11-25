import AppKit
import Theme

/// 더 보기 메뉴에서 고를 수 있는 것(spec 5.4).
enum MoreMenuAction: Hashable {
    case setReminder
    case moveToSpace
    case togglePin
    case toggleFormatBar
    /// 팔레트 키. 색 없음이면 `nil`.
    case setColor(String?)
    case openLibrary
    case findNote
    case newNote
    case closeWindow
    case toggleArchive
    case moveToTrash
}

/// 저장하지 못한 노트의 표시를 눌렀을 때 고를 수 있는 것.
enum ProblemMenuAction: Hashable {
    /// 이 앱에서 고친 내용으로 디스크의 파일을 덮어쓴다.
    case keepMine
    /// 디스크의 내용을 받아들이고 이 앱에서 고친 내용을 버린다.
    case keepDisk
    case retrySave
    /// 파일이 없어진 노트의 글을 새 노트로 옮긴다.
    case saveAsNewNote
    /// 파일이 없어진 노트의 글을 버리고 창을 닫는다.
    case discard
}

/// 노트 창의 메뉴를 만든다. 항목에 단축키를 넣지 않는다(규칙 4).
struct NoteMenuBuilder {
    let style: PanelStyle

    /// - Parameter isAvailable: 그 항목을 고르면 일어나는 일이 있는지. 여는 화면이 아직 이어지지 않은 항목은
    ///   자리를 그대로 둔 채 고를 수 없게 흐려 둔다(눌러도 아무 일이 없는 것을 내놓지 않는다).
    func moreMenu(
        isPinned: Bool, isArchived: Bool = false, showsFormatBar: Bool = false, selectedPaletteID: String?,
        isAvailable: (MoreMenuAction) -> Bool = { _ in true },
        handler: @escaping (MoreMenuAction) -> Void
    ) -> NSMenu {
        let menu = makeMenu()
        menu.items = [
            row("새 노트", symbol: "doc.badge.plus") { handler(.newNote) },
            separator(),
            row("리마인더 설정", symbol: "bell", isEnabled: isAvailable(.setReminder)) { handler(.setReminder) },
            row("스페이스 옮기기", symbol: "briefcase", isEnabled: isAvailable(.moveToSpace)) {
                handler(.moveToSpace)
            },
            row(isPinned ? "항상 위에 고정 해제" : "항상 위에 고정", symbol: "pin") { handler(.togglePin) },
            colorRow(selectedPaletteID: selectedPaletteID) { handler(.setColor($0)) },
            separator(),
            row("노트 찾기", symbol: "magnifyingglass") { handler(.findNote) },
            row("라이브러리", symbol: "rectangle.split.2x1", isEnabled: isAvailable(.openLibrary)) { handler(.openLibrary) },
            row(showsFormatBar ? "서식 막대 숨기기" : "서식 막대 보이기", symbol: "pencil", isEnabled: isAvailable(.toggleFormatBar)) {
                handler(.toggleFormatBar)
            },
            separator(),
            row("창 닫기", symbol: "xmark") { handler(.closeWindow) },
            row(isArchived ? "되돌리기" : "보관함으로", symbol: "archivebox") { handler(.toggleArchive) },
            row("휴지통으로 보내기", symbol: "trash") { handler(.moveToTrash) },
        ]
        return menu
    }

    func problemMenu(for problem: NoteProblem, handler: @escaping (ProblemMenuAction) -> Void) -> NSMenu {
        let menu = makeMenu()
        switch problem {
        case .conflict:
            menu.items = [
                info(problem.accessibilityLabel),
                row("내가 고친 내용으로 저장", symbol: nil) { handler(.keepMine) },
                row("파일의 내용으로 되돌리기", symbol: nil) { handler(.keepDisk) },
            ]
        case .saveFailed(let message):
            menu.items = [
                info(message),
                row("다시 저장", symbol: nil) { handler(.retrySave) },
            ]
        case .fileMissing:
            menu.items = [
                info(problem.accessibilityLabel),
                row("새 노트로 저장", symbol: nil) { handler(.saveAsNewNote) },
                row("버리기", symbol: nil) { handler(.discard) },
            ]
        }
        return menu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = style.theme.component(.noteMenuWidth)
        return menu
    }

    private func row(
        _ title: String, symbol: String?, isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let target = MenuActionTarget(action)
        let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.fire), keyEquivalent: "")
        item.target = target
        // 항목은 target을 붙잡지 않는다. 메뉴가 살아 있는 동안 함께 살도록 여기 맡긴다.
        item.representedObject = target
        item.isEnabled = isEnabled
        item.setAccessibilityLabel(title)
        item.view = PickerMenuRow(theme: style.theme, text: title,
                                  dot: symbol.flatMap { style.symbol($0, size: .menuIcon) }?.withSymbolConfiguration(
                                    .init(paletteColors: [style.color(isEnabled ? .text2 : .text3)])),
                                  selected: false, width: style.theme.component(.noteMenuWidth), command: true)
        return item
    }

    /// 구분선. 구분선 항목(`isSeparatorItem`)으로 두되 모습은 불투명 바탕의 `MenuSeparatorView`다.
    private func separator() -> NSMenuItem {
        MenuSeparatorView.item(theme: style.theme)
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.view = PickerMenuRow(theme: style.theme, text: text, dot: nil, selected: false, width: style.theme.component(.noteMenuWidth), command: true)
        return item
    }

    private func colorRow(selectedPaletteID: String?, onSelect: @escaping (String?) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: "노트 색", action: nil, keyEquivalent: "")
        item.view = ColorSwatchRowView(style: style, selectedPaletteID: selectedPaletteID, onSelect: onSelect)
        return item
    }
}

/// 메뉴 항목이 부르는 클로저를 든 대상.
final class MenuActionTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}
