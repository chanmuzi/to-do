import Foundation
import NotePanel
import Routing

/// 기능 모듈이 보낸 요청을 받아 그 일을 하는 모듈을 부르는 곳.
/// 노트 창 요청은 `NotePanelCoordinator`로 넘긴다. 아직 화면이 없는 요청은 기록만 한다.
final class AppRouter: Routing {
    /// 조립할 때 넣는다. `NotePanelCoordinator`가 이 라우터를 들고 있으므로 약하게 든다.
    weak var notePanels: NotePanelCoordinator?
    /// 아직 연결되지 않아 기록만 한 요청.
    private(set) var unhandled: [Route] = []

    func route(_ route: Route) {
        guard let notePanels else {
            logUnhandled(route)
            return
        }
        do {
            switch route {
            case .openNote(let id): try notePanels.open(id)
            case .newNote(let request): try notePanels.createNote(request)
            case .closeNoteWindow(let id): notePanels.closeWindow(id)
            case .toggleAllNotesHidden: notePanels.toggleAllHidden()
            case .openCapture, .openBrowse, .openLibrary, .openAIPanel, .openSettings, .openShortcuts,
                 .openReminderEditor, .openSpacePicker:
                logUnhandled(route)
            }
        } catch {
            AppLog.warning("요청을 처리하지 못했습니다(\(route)): \(error)")
        }
    }

    private func logUnhandled(_ route: Route) {
        unhandled.append(route)
        AppLog.warning("아직 연결되지 않은 요청입니다: \(route)")
    }
}
