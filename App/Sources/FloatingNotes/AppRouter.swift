import Foundation
import NotePanel
import Routing

extension Route {
    /// 이 요청을 받아 일하는 화면이 App에 이어져 있는지. 이어지지 않은 요청은 `AppRouter`가 기록만 한다.
    ///
    /// 화면을 이을 때 그 줄을 참 쪽으로 옮기고 `AppRouter.route(_:)`에서 그 화면을 부른다. 이것 하나로
    /// 그 화면을 여는 전역 단축키도 등록되기 시작한다(`AppCommand.isConnected`, `GlobalHotKeys`).
    /// 하는 일이 없는 키를 시스템 전체에서 차지하지 않기 위해서다(D-024).
    var isConnected: Bool {
        switch self {
        case .openNote, .newNote, .closeNoteWindow, .toggleAllNotesHidden: true
        // INTEGRATION(Capture): `.openCapture`를 위로 옮긴다.
        // INTEGRATION(Browse): `.openBrowse`를 위로 옮긴다.
        case .openCapture, .openBrowse, .openLibrary, .openAIPanel, .openSettings, .openShortcuts,
             .openReminderEditor, .openSpacePicker: false
        }
    }
}

/// 기능 모듈이 보낸 요청을 받아 그 일을 하는 모듈을 부르는 곳.
/// 노트 창 요청은 `NotePanelCoordinator`로 넘긴다. 아직 화면이 없는 요청(`Route.isConnected`가 거짓)은 기록만 한다.
///
/// 빠른 캡처와 노트 찾기는 `Route.isConnected`와 아래 `INTEGRATION` 표시 두 곳에서 잇는다. 그때 쓸 것:
/// - `notePanels.window(for:)`: 그 노트의 `NSWindow`(노트 찾기를 상단 줄 아래에 붙일 때).
/// - `notePanels.frontmostNoteID`: 맨 앞 노트(키 창인 노트, 없으면 보이는 것 가운데 가장 앞). `keyNoteID`는 키 창인 노트만.
final class AppRouter: Routing {
    /// 조립할 때 넣는다. `NotePanelCoordinator`가 이 라우터를 들고 있으므로 약하게 든다.
    weak var notePanels: NotePanelCoordinator?
    /// 사용자가 시킨 일을 하지 못했을 때 알리는 곳(제목, 까닭). 기본은 알림 창이다.
    var presentFailure: (String, Error) -> Void = { RouteFailureAlert.present(title: $0, error: $1) }
    /// 아직 연결되지 않아 기록만 한 요청.
    private(set) var unhandled: [Route] = []

    func route(_ route: Route) {
        guard route.isConnected, let notePanels else {
            logUnhandled(route)
            return
        }
        do {
            switch route {
            case .openNote(let id): try notePanels.open(id)
            case .newNote(let request): try notePanels.createNote(request)
            case .closeNoteWindow(let id): notePanels.closeWindow(id)
            case .toggleAllNotesHidden: notePanels.toggleAllHidden()
            case .openCapture:
                // INTEGRATION(Capture): 빠른 캡처 바를 여기서 띄운다(화면 가운데 위쪽, spec 4.1).
                logUnhandled(route)
            case .openBrowse:
                // INTEGRATION(Browse): 노트 찾기를 여기서 띄운다. `anchor`가 있으면
                // `notePanels.window(for: anchor)`의 상단 줄 아래에, 없으면 캡처 바 자리에(spec 4.1).
                logUnhandled(route)
            case .openLibrary, .openAIPanel, .openSettings, .openShortcuts, .openReminderEditor, .openSpacePicker:
                logUnhandled(route)
            }
        } catch {
            AppLog.warning("요청을 처리하지 못했습니다(\(route)): \(error)")
            // 눌렀는데 아무 일도 일어나지 않은 것처럼 보이지 않게 까닭을 보여 준다(디스크가 가득 참 등).
            if let title = Self.failureTitle(for: route) { presentFailure(title, error) }
        }
    }

    private static func failureTitle(for route: Route) -> String? {
        switch route {
        case .newNote: "새 노트를 만들지 못했습니다"
        case .openNote: "노트를 열지 못했습니다"
        default: nil
        }
    }

    private func logUnhandled(_ route: Route) {
        unhandled.append(route)
        AppLog.warning("아직 연결되지 않은 요청입니다: \(route)")
    }
}
