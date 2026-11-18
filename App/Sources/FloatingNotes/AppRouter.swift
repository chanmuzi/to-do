import Models
import Foundation
import FloatSettings
import NotePanel
import Library
import Reminders
import Routing

extension Route {
    /// 이 요청을 받아 일하는 화면이 App에 이어져 있는지. 이어지지 않은 요청은 `AppRouter`가 기록만 한다.
    ///
    /// 화면을 이을 때 그 줄을 참 쪽으로 옮기고 `AppRouter.route(_:)`에서 그 화면을 부른다. 이것 하나로
    /// 그 화면을 여는 전역 단축키도 등록되기 시작한다(`AppCommand.isConnected`, `GlobalHotKeys`).
    /// 하는 일이 없는 키를 시스템 전체에서 차지하지 않기 위해서다(D-024).
    var isConnected: Bool {
        switch self {
        case .openNote, .newNote, .closeNoteWindow, .toggleAllNotesHidden, .openCapture, .openBrowse, .openLibrary, .openSpacePicker, .openReminderEditor, .openSettings, .openShortcuts: true
        case .openAIPanel: false
        }
    }
}

/// 기능 모듈이 보낸 요청을 받아 그 일을 하는 모듈을 부르는 곳.
/// 노트 창 요청은 `NotePanelCoordinator`로, 빠른 캡처와 노트 찾기는 `QuickPanels`로 넘긴다.
/// 아직 화면이 없는 요청(`Route.isConnected`가 거짓)은 기록만 하고 `.unconnected`로 답한다.
/// 보낸 쪽은 답(`RouteResult`)을 보고 닫을지, 적던 글을 둘지, 포커스를 돌려줄지 정한다.
///
/// 노트 찾기와 캡처 바가 보낸 요청도 여기로 돌아온다: 고른 노트는 `.openNote`(창을 앞으로 가져오고 키 창으로
/// 만든다. 사용자가 고른 것이므로 D-025의 "앱이 시킨다"에 든다), "새 노트 만들기"와 캡처의 ⌘↵는 `.newNote`.
final class AppRouter: Routing {
    /// 조립할 때 넣는다. `NotePanelCoordinator`가 이 라우터를 들고 있으므로 약하게 든다.
    weak var notePanels: NotePanelCoordinator?
    /// 조립할 때 넣는다. 캡처 바와 노트 찾기가 이 라우터를 들고 있으므로 약하게 든다.
    weak var settingsWindow: SettingsCoordinator?
    weak var reminders: ReminderEditorCoordinator?
    weak var library: LibraryCoordinator?
    weak var quickPanels: QuickPanels?
    /// 사용자가 시킨 일을 하지 못했을 때 알리는 곳(제목, 까닭). 기본은 알림 창이다.
    var presentFailure: (String, Error) -> Void = { RouteFailureAlert.present(title: $0, error: $1) }
    /// 앱을 앞으로 가져온다. 사용자가 노트를 열거나 새로 만들라고 한 뒤에 부른다(D-025): 다른 앱이 앞에 있을 때
    /// 메뉴 막대 메뉴, 캡처 바의 ⌘↵, 노트 찾기, 알림의 "열기"로 연 노트에 곧바로 글을 쓸 수 있게 한다.
    /// 기본은 아무것도 하지 않는다(시험이 사용자의 앱을 뒤로 보내지 않게). `AppDelegate`가 넣는다.
    var activateApp: () -> Void = {}
    var onScheduleCreated: (@MainActor (NoteID, String) -> Void)?
    /// 아직 연결되지 않아 기록만 한 요청.
    private(set) var unhandled: [Route] = []

    func isConnected(_ route: Route) -> Bool {
        route.isConnected
    }

    /// 하지 못했으면 알림 창으로 까닭을 보여 준 뒤(창이 닫힌 뒤)에 `.failed`로 돌아온다.
    @discardableResult
    func route(_ route: Route) -> RouteResult {
        guard route.isConnected, let notePanels else { return logUnhandled(route) }
        do {
            switch route {
            case .openNote(let id):
                try notePanels.open(id)
                activateApp()
            case .newNote(let request):
                let id = try notePanels.createNote(request)
                request.draft.schedules?.forEach { onScheduleCreated?(id, $0.id) }
                activateApp()
            case .closeNoteWindow(let id): notePanels.closeWindow(id)
            case .toggleAllNotesHidden: notePanels.toggleAllHidden()
            case .openCapture:
                guard let quickPanels else { return logUnhandled(route) }
                quickPanels.toggleCapture()
            case .openBrowse(let anchor):
                guard let quickPanels else { return logUnhandled(route) }
                quickPanels.toggleBrowse(anchor: anchor)
            case .openLibrary:
                guard let library else { return logUnhandled(route) }
                library.show()
                activateApp()
            case .openSpacePicker(let id):
                guard let library else { return logUnhandled(route) }
                library.showSpacePicker(for: id, anchor: notePanels.window(for: id)?.contentView)
            case .openReminderEditor(let id):
                guard let reminders, let anchor = notePanels.reminderAnchor(for: id) else { return logUnhandled(route) }
                notePanels.flushPendingEdits()
                try reminders.show(id, anchor: anchor)
            case .openSettings, .openShortcuts:
                guard let settingsWindow else { return logUnhandled(route) }
                settingsWindow.show(route == .openShortcuts ? .shortcuts : nil)
                activateApp()
            case .openAIPanel:
                return logUnhandled(route)
            }
            return .handled
        } catch {
            AppLog.warning("요청을 처리하지 못했습니다(\(route)): \(error)")
            // 눌렀는데 아무 일도 일어나지 않은 것처럼 보이지 않게 까닭을 보여 준다(디스크가 가득 참 등).
            if let title = Self.failureTitle(for: route) { presentFailure(title, error) }
            return .failed
        }
    }

    private static func failureTitle(for route: Route) -> String? {
        switch route {
        case .newNote: "새 노트를 만들지 못했습니다"
        case .openNote: "노트를 열지 못했습니다"
        default: nil
        }
    }

    private func logUnhandled(_ route: Route) -> RouteResult {
        unhandled.append(route)
        AppLog.warning("아직 연결되지 않은 요청입니다: \(route)")
        return .unconnected
    }
}
