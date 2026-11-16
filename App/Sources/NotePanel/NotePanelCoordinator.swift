import AppKit
import Models
import Routing
import Store
import Theme

/// 떠 있는 노트 창 전부를 맡는 곳. App이 하나 만들어 들고, `Route`를 받아 이 타입의 메서드를 부른다.
///
/// - 노트 하나에 창 하나. 이미 떠 있는 노트를 열면 그 창을 앞으로 가져온다.
/// - 창의 틀, 핀, 열림 상태는 `WindowStateStore`에 남기고 `restoreOpenNotes()`로 되살린다.
/// - 노트 내용은 `NoteStoring`의 `load`, `update`, `scheduleUpdate`만 거쳐 읽고 쓴다.
public final class NotePanelCoordinator {
    /// 상단 줄 표시 방식. 바꾸면 떠 있는 창에 바로 반영된다.
    public var displayOptions = NotePanelDisplayOptions() {
        didSet { controllers.values.forEach { $0.refreshChrome(animated: false) } }
    }

    /// "노트 모두 숨기기"가 켜져 있는지(spec 4.3).
    public private(set) var areNotesHidden = false

    private let notes: any NoteStoring
    private let recorder: WindowStateRecorder
    private let log: (String) -> Void
    private var environment: NotePanelEnvironment!
    private(set) var controllers: [NoteID: NoteWindowController] = [:]
    /// 띄운 순서.
    private var order: [NoteID] = []
    private var storeObservation: StoreObservation?
    private var observers: [any NSObjectProtocol] = []

    /// - Parameters:
    ///   - router: 노트 창이 다른 기능을 부를 때(노트 찾기, 새 노트, AI 패널 등) 보내는 곳.
    ///   - makeBodyEditor: 본문 편집기를 만드는 곳. 주지 않으면 서식 없는 기본 편집기를 쓴다.
    ///   - log: 사용자에게 창으로 알릴 일이 아닌 문제를 남기는 곳.
    public init(
        theme: Theme,
        notes: any NoteStoring,
        windowStates: WindowStateStore,
        spaces: SpaceStore,
        router: any Routing,
        makeBodyEditor: @escaping NoteBodyEditorFactory = { PlainTextBodyEditor(theme: $0.theme) },
        log: @escaping (String) -> Void
    ) {
        self.notes = notes
        self.log = log
        recorder = WindowStateRecorder(store: windowStates, log: log)
        environment = NotePanelEnvironment(
            style: PanelStyle(theme: theme), notes: notes, spaces: spaces, router: router,
            recorder: recorder, makeBodyEditor: makeBodyEditor,
            options: { [unowned self] in displayOptions }, log: log
        )
        storeObservation = notes.observe { [weak self] in self?.storeDidChange($0) }
        observeAppearance(of: theme)
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    // MARK: - 열고 닫기

    /// 지난번에 떠 있던 노트를 제자리에 다시 띄운다. 띄운 노트를 돌려준다.
    /// 그사이 없어진 노트는 상태에서 지우고 넘어간다.
    @discardableResult
    public func restoreOpenNotes() -> [NoteID] {
        recorder.openNoteIDs.filter { id in
            do {
                try open(id, focus: false)
                return true
            } catch StoreError.noteNotFound {
                log("떠 있던 노트의 파일이 없어 창을 되살리지 않습니다: \(id)")
                recorder.forget(id)
                return false
            } catch {
                log("노트 창을 되살리지 못했습니다(\(id)): \(error)")
                return false
            }
        }
    }

    /// 노트 창을 띄운다. 이미 떠 있으면 앞으로 가져온다.
    /// - Parameters:
    ///   - nextTo: 처음 띄우는 노트를 이 노트 옆에 둔다. 없으면 지금 쓰는 노트 옆, 그것도 없으면 화면 오른쪽 위.
    ///   - focus: 본문에 입력 커서를 둔다.
    public func open(_ id: NoteID, nextTo: NoteID? = nil, focus: Bool = true) throws {
        if areNotesHidden { toggleAllHidden() }
        if let controller = controllers[id] {
            controller.show(focus: focus)
            return
        }
        // 편집용으로 열 때는 목록의 값이 아니라 load의 값을 쓴다(충돌 기준이 여기서 잡힌다).
        let note = try notes.load(id)
        let state = recorder.state(for: id)
        let controller = NoteWindowController(
            note: note, frame: frame(for: state, nextTo: nextTo), isPinned: state.isPinned,
            environment: environment
        )
        controller.coordinator = self
        controllers[id] = controller
        order.append(id)
        controller.show(focus: focus)
    }

    /// 새 노트를 만들어 지금 노트 옆에 띄운다. 핀이 켜진 채로 뜬다(spec 4.1).
    @discardableResult
    public func createNote(_ request: NewNoteRequest = NewNoteRequest()) throws -> NoteID {
        let note = try notes.create(request.draft)
        try open(note.id, nextTo: request.nextTo, focus: true)
        return note.id
    }

    /// 창만 내린다. 노트는 남는다. 미뤄 둔 변경을 쓰지 못하면 창을 남기고 상단 줄에 표시한다.
    public func closeWindow(_ id: NoteID) {
        guard let controller = controllers[id], controller.flushBeforeClosing() else { return }
        recorder.recordClosed(id)
        discard(id)
    }

    /// 노트를 휴지통으로 보내고 창을 내린다. 확인 창을 띄우지 않는다(spec 5.3).
    public func moveToTrash(_ id: NoteID) {
        controllers[id]?.root.topRow.endTitleEditing()
        do {
            try notes.moveToTrash(id)
        } catch {
            if let controller = controllers[id] {
                controller.handleStoreFailure(error)
            } else {
                log("노트를 휴지통으로 보내지 못했습니다(\(id)): \(error)")
            }
            return
        }
        noteDisappeared(id)
    }

    /// 떠 있는 노트를 한꺼번에 감추거나 제자리에 되돌린다.
    public func toggleAllHidden() {
        areNotesHidden.toggle()
        order.compactMap { controllers[$0] }.forEach { $0.setHidden(areNotesHidden) }
    }

    // MARK: - 창마다

    /// 떠 있는 노트(띄운 순서).
    public var openNoteIDs: [NoteID] { order }

    /// 지금 글을 쓰고 있는 노트(키 창). 없으면 `nil`.
    public var keyNoteID: NoteID? {
        order.last { controllers[$0]?.panel.isKeyWindow == true }
    }

    public func snapshot(of id: NoteID) -> NoteWindowSnapshot? {
        controllers[id]?.snapshot
    }

    public func setPinned(_ pinned: Bool, for id: NoteID) {
        controllers[id]?.setPinned(pinned)
    }

    /// 노트 색을 바꾼다. `nil`이면 색 없음.
    public func setColor(_ colorID: PaletteID?, for id: NoteID) {
        controllers[id]?.setColor(colorID?.rawValue)
    }

    /// 노트 창을 키 창으로 만들고 본문에 커서를 둔다.
    public func focusBody(of id: NoteID) {
        controllers[id]?.focusBody()
    }

    /// 더 보기 메뉴를 띄운다(키보드로 열 때).
    public func popUpMoreMenu(for id: NoteID) {
        controllers[id]?.popUpMoreMenu()
    }

    /// 확인용: 마우스 위치와 상관없이 호버 상태를 정한다. `nil`이면 마우스를 따른다.
    public func setHoverOverride(_ hovered: Bool?, for id: NoteID) {
        controllers[id]?.hoverOverride = hovered
    }

    // MARK: - 안쪽

    /// 노트가 없어졌다(휴지통으로 갔거나 파일이 지워짐). 창을 내리고 창 상태도 지운다.
    func noteDisappeared(_ id: NoteID) {
        discard(id)
        recorder.forget(id)
    }

    private func discard(_ id: NoteID) {
        controllers.removeValue(forKey: id)?.discardWindow()
        order.removeAll { $0 == id }
    }

    private func storeDidChange(_ change: StoreChange) {
        if change.kind == .removed {
            noteDisappeared(change.id)
        } else {
            controllers[change.id]?.storeDidChange(change)
        }
    }

    private func observeAppearance(of theme: Theme) {
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.controllers.values.forEach { $0.themeDidChange() } }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: Theme.didChangeNotification, object: theme, queue: nil, using: refresh
            ),
            // 대비 증가, 동작 줄이기(spec 15, 17).
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
                queue: .main, using: refresh
            ),
        ]
    }

    private func frame(for state: NoteWindowState, nextTo: NoteID?) -> CGRect {
        let policy = environment.sizePolicy
        let placement = environment.placement
        let screens = NSScreen.screens
        guard let main = (NSScreen.main ?? screens.first)?.visibleFrame else {
            return CGRect(x: 0, y: 0, width: policy.defaultWidth, height: policy.minHeight)
        }
        if let saved = state.frame?.cgRect {
            let sized = CGRect(
                x: saved.minX, y: saved.minY, width: policy.clampedWidth(saved.width),
                height: max(saved.height, policy.minHeight)
            )
            return placement.restoredFrame(
                saved: sized, screens: screens.map(\.frame), main: main,
                handleHeight: environment.theme.shape(.chromeHeight)
            )
        }
        let size = CGSize(width: policy.defaultWidth, height: policy.minHeight)
        let occupied = order.compactMap { controllers[$0]?.panel.frame }
        let anchorID = nextTo.flatMap { controllers[$0] != nil ? $0 : nil } ?? keyNoteID ?? order.last
        guard let anchor = anchorID.flatMap({ controllers[$0]?.panel.frame }) else {
            return placement.initialFrame(size: size, visibleFrame: main, occupied: occupied)
        }
        let visible = screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? main
        return placement.frame(nextTo: anchor, size: size, visibleFrame: visible, occupied: occupied)
    }
}
