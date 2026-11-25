import AppKit
import Capture
import Models
import NotePanel
import Routing
import Store

/// 앱이 띄우는 짧은 알림(D-041). 노트 창과 캡처 바는 서로를 모르고 알림도 모른다. 여기서만 잇는다.
///
/// - 휴지통으로 보내면 "휴지통으로 보냈습니다"와 "되돌리기". 누르면 ⌘Z와 같이 되살린다. 어느 쪽으로 되살리든,
///   또는 "바로 뒤"가 지나 되돌릴 수 없게 되면 알림을 거둔다.
/// - 캡처 바에서 ↵로 넣으면 그 노트의 이름("제목"에 넣었습니다, 제목이 없으면 오늘 노트)과 "열기". 누르면
///   그 노트를 띄운다. 그 노트의 창이 이미 보이면 알림을 띄우지 않는다(줄이 그 창에 바로 보인다).
final class AppToasts {
    static let trashKind = "trash"
    static let captureKind = "capture"
    static let trashMessage = "휴지통으로 보냈습니다"
    static func trashMessage(removed: [ScheduleItem.Kind]) -> String {
        guard let first = removed.first else { return trashMessage }
        let name = removed.allSatisfy { $0 == first } ? (first == .event ? "일정" : "리마인더") : "예정"
        return "\(trashMessage). \(name) \(removed.count)개도 지웠습니다"
    }
    var removedExternalItems: (NoteID) -> [ScheduleItem.Kind] = { _ in [] }
    static let undoTitle = "되돌리기"
    static let openTitle = "열기"
    static let todayNoteName = "오늘 노트"

    let presenter: ToastPresenter
    private let notePanels: NotePanelCoordinator
    private let notes: any NoteStoring
    private let router: any Routing
    /// 마우스가 있는 화면. 캡처 바와 같은 화면에 띄운다. 시험에서 바꿔 넣는다.
    var pointerScreen: () -> NSScreen? = {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// - Parameter undoTrash: 휴지통 되돌리기(⌘Z와 같은 길. 되살리지 못하면 알리는 일까지 한다).
    init(
        presenter: ToastPresenter, notePanels: NotePanelCoordinator, capture: CaptureCoordinator,
        notes: any NoteStoring, router: any Routing, undoTrash: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.notePanels = notePanels
        self.notes = notes
        self.router = router
        notePanels.onMovedToTrash = { [unowned self] id, screen, frame in
            presenter.show(
                .init(kind: Self.trashKind, message: Self.trashMessage(removed: removedExternalItems(id)), actionTitle: Self.undoTitle), on: screen, noteFrame: frame
            ) { [unowned self] in
                // 그사이 되돌릴 수 없게 됐으면 아무것도 하지 않는다(알림도 이미 거둬졌어야 한다).
                if self.notePanels.canUndoTrash { undoTrash() }
            }
        }
        notePanels.onTrashUndoEnded = { presenter.dismiss(kind: Self.trashKind) }
        capture.onCaptured = { [unowned self] in captured(into: $0) }
    }

    /// 캡처한 줄이 들어간 노트를 알린다. 그 노트의 창이 보이면 알리지 않는다.
    func captured(into id: NoteID) {
        guard notePanels.window(for: id)?.isVisible != true else { return }
        presenter.show(
            .init(kind: Self.captureKind, message: Self.captureMessage(title: title(of: id)), actionTitle: Self.openTitle),
            on: pointerScreen()
        ) { [unowned self] in
            router.route(.openNote(id))
        }
    }

    func scheduleDeletion(_ items: [ScheduleItem], in id: NoteID, token: UUID, undo: @escaping () -> Void) {
        guard let window = notePanels.window(for: id) else { return }
        presenter.show(.init(kind: token.uuidString, message: Self.scheduleDeletionMessage(items),
                             actionTitle: Self.undoTitle), on: window.screen, noteFrame: window.frame, action: undo)
    }

    static func scheduleDeletionMessage(_ items: [ScheduleItem]) -> String {
        if items.count == 1 { return items[0].kind == .event ? "일정도 지웠습니다" : "리마인더도 지웠습니다" }
        return "예정 \(items.count)개도 지웠습니다"
    }

    static func captureMessage(title: String?) -> String {
        "“\(title ?? todayNoteName)”에 넣었습니다"
    }

    private func title(of id: NoteID) -> String? {
        guard let title = try? notes.load(id).title, !title.allSatisfy(\.isWhitespace) else { return nil }
        return title
    }
}
