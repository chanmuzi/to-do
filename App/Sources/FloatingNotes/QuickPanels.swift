import AppKit
import Browse
import Capture
import Models
import NotePanel
import Routing
import Store
import Theme

/// 빠른 캡처 바와 노트 찾기를 들고, 둘과 노트 창 사이의 규칙을 맡는 곳(D-032).
///
/// 두 화면은 서로를 모르고 노트 창도 모른다. 여기서만 이어진다.
/// - 한 번에 하나만 열린다. 하나가 열려 있을 때 다른 것을 열면 먼저 것이 닫힌다.
/// - 키 입력: 두 화면은 앱이 앞에 있지 않아도 키 창이 되어 글을 받는다. 닫힐 때는 열기 전에 키 창이던
///   노트에게 키 창을 돌려준다(`KeyFocusReturn`). 그런 노트가 없었으면 아무 창도 키 창으로 만들지 않는다
///   (앱이 앞에 있지 않았다면 시스템이 앞에 있던 앱에 키 입력을 돌려준다).
/// - 넣지 못한 캡처와 열지 못한 노트 찾기는 기록만 하지 않고 알림 창으로 보여 준다.
final class QuickPanels {
    static let captureFailureTitle = "캡처한 글을 넣지 못했습니다"
    static let browseFailureTitle = "노트 목록을 읽지 못했습니다"

    let capture: CaptureCoordinator
    let browse: BrowseCoordinator
    private let notePanels: NotePanelCoordinator
    private var focusReturn = KeyFocusReturn()
    /// 한쪽을 닫고 다른 쪽을 여는 중이다. 이때 닫히는 쪽의 알림으로는 포커스를 돌려주지 않는다.
    private var isSwitching = false

    /// 사용자가 시킨 일을 하지 못했을 때 알리는 곳(제목, 까닭). 기본은 알림 창이다.
    var presentFailure: (String, Error) -> Void = { RouteFailureAlert.present(title: $0, error: $1) }
    /// 지금 키 창인 노트. 시험은 실제 키 창을 만들지 않으므로 바꿔 넣는다.
    var currentKeyNote: () -> NoteID?
    /// 그 노트에게 키 창을 돌려준다. 시험에서 바꿔 넣는다.
    var returnKey: (NoteID) -> Void

    /// - Parameter windowStates: 노트 창에 넘긴 것과 같은 객체. 노트 찾기가 떠 있는 노트와 핀, 연 때를 여기서 읽는다.
    init(
        theme: Theme, notes: any NoteStoring, spaces: SpaceStore, windowStates: WindowStateStore,
        router: any Routing, notePanels: NotePanelCoordinator, log: @escaping @MainActor (String) -> Void
    ) {
        self.notePanels = notePanels
        capture = CaptureCoordinator(theme: theme, notes: notes, spaces: spaces, router: router, log: log)
        browse = BrowseCoordinator(
            theme: theme, notes: notes, spaces: spaces, router: router, windowStates: windowStates, log: log
        )
        currentKeyNote = { [unowned notePanels] in notePanels.keyNoteID }
        returnKey = { [unowned notePanels] in notePanels.returnKey(to: $0) }
        capture.onDismiss = { [unowned self] in panelDismissed(returnsFocus: $0) }
        browse.onDismiss = { [unowned self] in panelDismissed(returnsFocus: $0) }
        capture.onFailure = { [unowned self] in presentFailure(Self.captureFailureTitle, $0) }
        browse.onFailure = { [unowned self] in presentFailure(Self.browseFailureTitle, $0) }
    }

    /// 둘 가운데 하나라도 열려 있는지.
    var isAnyVisible: Bool { capture.isVisible || browse.isVisible }

    /// 빠른 캡처 바를 띄우거나, 떠 있으면 닫는다(⌃⌥N, 메뉴).
    func toggleCapture() {
        if capture.isVisible {
            capture.hide()
            return
        }
        beginSession(closing: browse.isVisible ? { [browse] in browse.hide() } : nil)
        capture.show()
    }

    /// 노트 찾기를 띄우거나, 떠 있으면 닫는다(⌘P, 돋보기, 메뉴).
    /// - Parameter anchor: 이 노트의 창 상단 줄 아래에 붙이고 목록에서 그 노트를 뺀다. 없거나 그 창이
    ///   보이지 않으면 화면 가운데 위쪽에 띄우고 아무 노트도 빼지 않는다.
    func toggleBrowse(anchor: NoteID?) {
        if browse.isVisible {
            browse.hide()
            return
        }
        beginSession(closing: capture.isVisible ? { [capture] in capture.hide() } : nil)
        let placement = BrowseAnchor.resolve(anchor) { [notePanels] in notePanels.window(for: $0) }
        browse.show(anchoredTo: placement.window, excluding: placement.excluded)
    }

    /// 여는 화면이 키 창을 가져가기 전에, 지금 키 입력을 받는 노트를 적어 둔다.
    /// 다른 쪽이 열려 있었으면 그쪽을 닫고, 그쪽이 열릴 때 적어 둔 것을 그대로 이어받는다
    /// (지금 키 창은 닫히는 그 화면이지 노트가 아니다).
    private func beginSession(closing hideOther: (() -> Void)?) {
        guard let hideOther else {
            focusReturn.begin(keyNote: currentKeyNote())
            return
        }
        isSwitching = true
        hideOther()
        isSwitching = false
    }

    private func panelDismissed(returnsFocus: Bool) {
        guard !isSwitching else { return }
        if let note = focusReturn.end(returnsFocus: returnsFocus) { returnKey(note) }
    }
}
