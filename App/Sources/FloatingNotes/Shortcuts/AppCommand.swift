import Models
import Routing

/// 단축키와 메뉴가 시키는 앱의 동작. 하는 일은 `AppCommandDispatcher`에 있다.
nonisolated enum AppCommand: String, Hashable, Sendable, CaseIterable {
    // 어디서나
    case quickCapture
    case toggleNotesHidden
    case library
    case requestAgent
    // 노트 창
    case newNote
    case findNote
    case openAgentWindow
    case moreMenu
    case enlargeBody, reduceBody, resetBodySize
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

extension AppCommand {
    /// 이 동작이 여는 화면이 App에 이어져 있는지(`Route.isConnected`). 노트 창에 하는 동작은 언제나 참이다.
    /// 전역 단축키는 이것이 참인 동작만 등록한다: 아직 하는 일이 없는 키를 시스템 전체에서 가져가지 않는다.
    var isConnected: Bool {
        switch self {
        case .quickCapture: Route.openCapture.isConnected
        case .toggleNotesHidden: Route.toggleAllNotesHidden.isConnected
        case .library: Route.openLibrary.isConnected
        case .requestAgent: Route.requestAgent.isConnected
        case .findNote: Route.openBrowse(anchor: nil).isConnected
        case .settings: Route.openSettings.isConnected
        case .shortcuts: Route.openShortcuts.isConnected
        case .newNote: Route.newNote(NewNoteRequest()).isConnected
        // 화면이 아직 없다(`AppCommandDispatcher`가 기록만 한다).
        case .findInNote, .searchAll: false
        // 리마인더 설정, 스페이스 옮기기는 지금 노트가 있어야 요청이 된다. 요청 종류는 노트와 상관없다.
        case .setReminder: Route.openReminderEditor(NoteID(rawValue: "")).isConnected
        case .moveToSpace: Route.openSpacePicker(NoteID(rawValue: "")).isConnected
        case .openAgentWindow, .enlargeBody, .reduceBody, .resetBodySize, .moreMenu, .nextNote, .editTitle, .togglePin, .closeWindow: true
        }
    }
}
