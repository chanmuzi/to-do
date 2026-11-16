import AppKit
import Models
import NotePanel
import Routing

/// `AppCommand`를 실제 일로 바꾸는 곳. 메뉴 막대 메뉴, 앱 메뉴의 단축키, 전역 단축키가 모두 여기로 온다.
/// 다른 화면을 여는 일은 `Routing`으로 보내고, 지금 노트 창에 하는 일은 `NotePanelCoordinator`에 시킨다.
final class AppCommandDispatcher: NSObject, NSMenuItemValidation {
    private let router: any Routing
    private let notePanels: NotePanelCoordinator
    /// 사용자가 시킨 일을 하지 못했을 때 알리는 곳(제목, 까닭). 기본은 알림 창이다.
    var presentFailure: (String, Error) -> Void = { RouteFailureAlert.present(title: $0, error: $1) }
    /// 편집기 같은 첫 응답자에게 넘길 실행 취소. 테스트에서 바꿔 넣는다.
    var forwardUndo: (Any?) -> Void = { NSApplication.shared.sendAction(Selector(("undo:")), to: nil, from: $0) }
    /// 앱을 끝낸다. 테스트에서 바꿔 넣는다.
    var quit: () -> Void = { NSApplication.shared.terminate(nil) }
    /// 아직 화면이 없어 기록만 한 동작(노트 안에서 찾기, 전체 검색).
    private(set) var unavailable: [AppCommand] = []

    init(router: any Routing, notePanels: NotePanelCoordinator) {
        self.router = router
        self.notePanels = notePanels
    }

    func perform(_ command: AppCommand) {
        let note = notePanels.keyNoteID
        switch command {
        case .quickCapture: router.route(.openCapture)
        case .toggleNotesHidden: router.route(.toggleAllNotesHidden)
        case .library: router.route(.openLibrary)
        case .aiPanel: router.route(.openAIPanel(context: note))
        case .newNote: router.route(.newNote(NewNoteRequest(nextTo: note)))
        case .findNote: router.route(.openBrowse(anchor: note))
        case .settings: router.route(.openSettings)
        case .shortcuts: router.route(.openShortcuts)
        case .nextNote: notePanels.focusNextNote()
        case .closeWindow:
            if let note {
                router.route(.closeNoteWindow(note))
            } else {
                // 노트가 아닌 창(뒤 단계의 라이브러리, 설정)은 보통 창처럼 닫는다.
                NSApplication.shared.keyWindow?.performClose(nil)
            }
        case .moreMenu: note.map(notePanels.popUpMoreMenu(for:))
        case .editTitle: note.map(notePanels.beginTitleEditing(for:))
        case .togglePin:
            guard let note, let snapshot = notePanels.snapshot(of: note) else { return }
            notePanels.setPinned(!snapshot.isPinned, for: note)
        case .setReminder: note.map { router.route(.openReminderEditor($0)) }
        case .moveToSpace: note.map { router.route(.openSpacePicker($0)) }
        case .findInNote, .searchAll:
            unavailable.append(command)
            AppLog.warning("아직 만들지 않은 동작입니다: \(command.rawValue)")
        }
    }

    /// 메뉴 막대 메뉴에서 고른 것(spec 4.3).
    func performStatusMenu(_ action: StatusMenuAction) {
        switch action {
        case .newNote: perform(.newNote)
        case .quickCapture: perform(.quickCapture)
        // 메뉴 막대에서 연 노트 찾기는 노트에 붙지 않고 화면 가운데 위쪽에 뜬다(spec 4.1, D-030).
        case .findNote: router.route(.openBrowse(anchor: nil))
        case .library: perform(.library)
        case .aiPanel: perform(.aiPanel)
        case .toggleNotesHidden: perform(.toggleNotesHidden)
        case .settings: perform(.settings)
        case .shortcuts: perform(.shortcuts)
        case .quit: quit()
        }
    }

    /// 앱 메뉴의 항목이 부른다. 항목의 `representedObject`에 동작 이름이 들어 있다.
    @objc func performMenuCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let command = AppCommand(rawValue: name) else {
            AppLog.warning("동작이 붙지 않은 메뉴 항목입니다: \(sender.title)")
            return
        }
        perform(command)
    }

    /// 앱 메뉴가 열릴 때 항목마다 불린다. "노트 모두 숨기기"는 숨긴 중이면 "노트 모두 보이기"가 된다.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.representedObject as? String == AppCommand.toggleNotesHidden.rawValue {
            menuItem.title = notePanels.areNotesHidden ? StatusMenuModel.showAllTitle : StatusMenuModel.hideAllTitle
        }
        return true
    }

    /// ⌘Z. 방금 노트를 휴지통으로 보냈으면 그 노트와 창을 되살리고(spec 5.3), 아니면 글의 실행 취소로 넘긴다.
    @objc func undoOrRestoreTrash(_ sender: Any?) {
        guard notePanels.canUndoTrash else {
            forwardUndo(sender)
            return
        }
        do {
            try notePanels.undoTrash()
        } catch {
            AppLog.warning("휴지통으로 보낸 노트를 되살리지 못했습니다: \(error)")
            presentFailure("노트를 되살리지 못했습니다", error)
        }
    }
}
