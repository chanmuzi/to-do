/// 단축키와 메뉴가 시키는 앱의 동작. 하는 일은 `AppCommandDispatcher`에 있다.
nonisolated enum AppCommand: String, Hashable, Sendable, CaseIterable {
    // 어디서나
    case quickCapture
    case toggleNotesHidden
    case library
    case aiPanel
    // 노트 창
    case newNote
    case findNote
    case moreMenu
    case nextNote
    case editTitle
    case togglePin
    case setReminder
    case moveToSpace
    case findInNote
    case searchAll
    case closeWindow
    case settings
    case shortcuts
}
