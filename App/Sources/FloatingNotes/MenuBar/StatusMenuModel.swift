/// 메뉴 막대 메뉴에서 고를 수 있는 것(spec 4.3).
nonisolated enum StatusMenuAction: Hashable, Sendable {
    case newNote
    case quickCapture
    case findNote
    case library
    case requestAgent
    case toggleNotesHidden
    case settings
    case shortcuts
    case quit
}

extension StatusMenuAction {
    /// 고르면 일어나는 일이 있는지. 여는 화면이 아직 이어지지 않은 항목(`AppCommand.isConnected`)은 메뉴에
    /// 자리와 이름을 그대로 두되(spec 4.3의 항목과 차례) 고를 수 없게 흐려 둔다(D-034).
    var isConnected: Bool {
        switch self {
        case .newNote: AppCommand.newNote.isConnected
        case .quickCapture: AppCommand.quickCapture.isConnected
        case .findNote: AppCommand.findNote.isConnected
        case .library: AppCommand.library.isConnected
        case .requestAgent: AppCommand.requestAgent.isConnected
        case .toggleNotesHidden: AppCommand.toggleNotesHidden.isConnected
        case .settings: AppCommand.settings.isConnected
        case .shortcuts: AppCommand.shortcuts.isConnected
        case .quit: true
        }
    }
}

/// 메뉴 막대 메뉴의 한 칸.
nonisolated enum StatusMenuEntry: Hashable, Sendable {
    /// - Parameter symbol: 왼쪽 14pt 아이콘의 SF Symbols 이름(spec 18.2). 종료에는 없다.
    case item(title: String, symbol: String?, action: StatusMenuAction)
    case separator

    var title: String? {
        if case .item(let title, _, _) = self { title } else { nil }
    }
}

/// 메뉴 막대 메뉴의 내용(spec 4.3, 화면 8). 순서와 이름은 `tokens.json`의 `navigation.menuBar`와 같다.
/// 단축키는 적지 않는다(규칙 4).
nonisolated enum StatusMenuModel {
    static let hideAllTitle = "노트 모두 숨기기"
    static let showAllTitle = "노트 모두 보이기"

    /// - Parameter areNotesHidden: 노트를 숨긴 중이면 숨기기 자리에 "노트 모두 보이기"가 온다.
    static func entries(areNotesHidden: Bool) -> [StatusMenuEntry] {
        [
            .item(title: "새 노트", symbol: "plus", action: .newNote),
            .item(title: "빠른 캡처", symbol: "terminal", action: .quickCapture),
            .separator,
            .item(title: "노트 찾기", symbol: "magnifyingglass", action: .findNote),
            .item(title: "라이브러리", symbol: "sidebar.left", action: .library),
            .item(title: "에이전트에게 요청", symbol: "sparkle", action: .requestAgent),
            .separator,
            areNotesHidden
                ? .item(title: showAllTitle, symbol: "eye", action: .toggleNotesHidden)
                : .item(title: hideAllTitle, symbol: "eye.slash", action: .toggleNotesHidden),
            .separator,
            .item(title: "설정", symbol: "slider.horizontal.3", action: .settings),
            .item(title: "단축키", symbol: "keyboard", action: .shortcuts),
            .separator,
            .item(title: "종료", symbol: nil, action: .quit),
        ]
    }
}
