import AppKit
import Models
import Routing
import Theme

/// 노트 창 하나. 창과 뷰를 만들고, 상단 줄의 상태를 정하고, 버튼과 메뉴의 동작을 저장소와 라우터로 넘긴다.
/// 저장소 쪽은 `NoteWindowController+Store`, 창 크기 쪽은 `NoteWindowController+Sizing`에 있다.
final class NoteWindowController: NSObject {
    let noteID: NoteID
    let panel: NotePanelWindow
    let environment: NotePanelEnvironment
    let root: NoteRootView
    let editor: any NoteBodyEditing
    weak var coordinator: NotePanelCoordinator?

    var note: Note
    var problem: NoteProblem?
    private(set) var isPinned: Bool
    private(set) var isShown = false
    private var isPointerInside = false
    /// 확인용 실행에서 마우스 위치와 상관없이 호버 상태를 정한다.
    var hoverOverride: Bool? {
        didSet { refreshChrome(animated: true) }
    }

    // 창 크기(`+Sizing`)
    var contentHeight: CGFloat = 0
    var liveResizeTop: CGFloat?
    /// 높이가 움직이는 중이면 그 목표.
    var heightTarget: CGFloat?
    var heightAnimation: Task<Void, Never>?
    private var heightChangedDuringLayout = false

    private var reminderRefresh: Task<Void, Never>?

    init(note: Note, frame: CGRect, isPinned: Bool, environment: NotePanelEnvironment) {
        self.noteID = note.id
        self.note = note
        self.isPinned = isPinned
        self.environment = environment
        editor = environment.makeBodyEditor(NoteBodyEditorContext(theme: environment.theme, noteID: note.id))
        editor.text = note.body
        root = NoteRootView(style: environment.style, bodyView: editor.view)
        panel = NotePanelWindow(contentRect: frame)
        super.init()
        panel.contentView = root
        panel.delegate = self
        panel.setPinned(isPinned)
        applySizeLimits()
        connect()
        refreshChrome(animated: false)
        // 배치하면 편집기가 내용 높이를 알려 온다. 창을 보이기 전에 높이를 맞춘다.
        root.layoutSubtreeIfNeeded()
        applyContentHeight(animated: false)
    }

    isolated deinit {
        reminderRefresh?.cancel()
        heightAnimation?.cancel()
    }

    var isHovered: Bool { hoverOverride ?? isPointerInside }

    var snapshot: NoteWindowSnapshot {
        NoteWindowSnapshot(
            noteID: noteID, frame: panel.frame, isPinned: isPinned, level: panel.level.rawValue,
            isVisible: panel.isVisible, isKey: panel.isKeyWindow, isHovered: isHovered,
            windowNumber: panel.windowNumber, problem: problem.map { "\($0)" }
        )
    }

    // MARK: - 띄우고 내리기

    /// 창을 앞에 띄운다. 앱을 앞으로 가져오지 않는다.
    func show(focus: Bool) {
        panel.orderFrontRegardless()
        if !isShown {
            isShown = true
            environment.recorder.recordOpened(noteID, frame: panel.frame, isPinned: isPinned)
        }
        if focus { focusBody() }
        isPointerInside = root.containsPointer
        refreshChrome(animated: false)
    }

    func focusBody() {
        panel.makeKeyAndOrderFront(nil)
        editor.focus()
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// 창을 없앤다. 상태를 남기는 일은 부르는 쪽이 한다.
    func discardWindow() {
        reminderRefresh?.cancel()
        heightAnimation?.cancel()
        isShown = false
        panel.delegate = nil
        panel.close()
    }

    // MARK: - 상단 줄

    func refreshChrome(animated: Bool) {
        let state = TopRowState(
            note: note,
            space: note.spaceID.flatMap { environment.spaces.space(for: $0) },
            isPinned: isPinned,
            isHovered: isHovered,
            isEditingTitle: root.topRow.isEditingTitle,
            problem: problem,
            options: environment.options(),
            now: Date(),
            calendar: .current
        )
        root.topRow.apply(state, animated: animated)
        root.setHoverControlsAlpha(state.hoverControlsAlpha, animated: animated)
        root.background.setPalette(note.colorID?.rawValue, animated: animated)
        panel.title = state.title
        scheduleReminderRefresh()
    }

    func themeDidChange() {
        root.refreshTheme()
        applySizeLimits()
        refreshChrome(animated: false)
        root.layoutSubtreeIfNeeded()
        applyContentHeight(animated: false)
    }

    /// 리마인더 표시가 달라지는 때(임박, 지남, 날짜 바뀜)에 다시 그린다.
    private func scheduleReminderRefresh() {
        reminderRefresh?.cancel()
        reminderRefresh = nil
        let now = Date()
        guard let reminder = note.reminder,
              let next = ReminderPresentation.nextRefresh(
                  reminder: reminder, now: now, options: environment.options(), calendar: .current
              )
        else { return }
        let delay = next.timeIntervalSince(now)
        reminderRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshChrome(animated: true)
        }
    }

    // MARK: - 동작

    private func connect() {
        root.onHoverChange = { [unowned self] inside in
            isPointerInside = inside
            refreshChrome(animated: true)
        }
        editor.onTextChange = { [unowned self] text in
            mutate(deferred: true) { $0.body = text }
        }
        editor.onContentHeightChange = { [unowned self] height in
            contentHeight = height
            // 너비가 바뀌어 온 알림은 배치 도중이다. 그때는 배치가 끝난 뒤(onLayout)에 맞춘다.
            if root.isLayingOut {
                heightChangedDuringLayout = true
            } else {
                applyContentHeight(animated: true)
            }
        }
        root.onLayout = { [unowned self] in
            guard heightChangedDuringLayout else { return }
            heightChangedDuringLayout = false
            applyContentHeight(animated: false)
        }

        let router = environment.router
        let id = noteID
        root.topRow.actions = TopRowView.Actions(
            search: { router.route(.openBrowse(anchor: id)) },
            more: { [unowned self] anchor in popUpMoreMenu(from: anchor) },
            add: { router.route(.newNote(NewNoteRequest(nextTo: id))) },
            reminder: { router.route(.openReminderEditor(id)) },
            pin: { [unowned self] in setPinned(!isPinned) },
            problem: { [unowned self] anchor in popUpProblemMenu(from: anchor) },
            titleChanged: { [unowned self] title in mutate(deferred: true) { $0.title = title } },
            titleEditingChanged: { [unowned self] _ in refreshChrome(animated: true) },
            titleReturned: { [unowned self] in editor.focus() }
        )
        root.cornerButtons.closeButton.onPress = { router.route(.closeNoteWindow(id)) }
        root.cornerButtons.trashButton.onPress = { [unowned self] in coordinator?.moveToTrash(noteID) }
    }

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        panel.setPinned(pinned)
        environment.recorder.recordPinned(noteID, isPinned: pinned)
        refreshChrome(animated: true)
    }

    func setColor(_ paletteID: String?) {
        mutate(deferred: false) { $0.colorID = paletteID.map(PaletteID.init(rawValue:)) }
        refreshChrome(animated: true)
    }

    /// 더 보기 메뉴(spec 5.4). 단축키로 열 때는 `anchor` 없이 부른다.
    func popUpMoreMenu(from anchor: NSView? = nil) {
        let router = environment.router
        let id = noteID
        let menu = NoteMenuBuilder(style: environment.style).moreMenu(
            isPinned: isPinned, selectedPaletteID: note.colorID?.rawValue
        ) { [weak self] action in
            switch action {
            case .setReminder: router.route(.openReminderEditor(id))
            case .moveToSpace: router.route(.openSpacePicker(id))
            case .togglePin: self?.setPinned(self?.isPinned == false)
            case .setColor(let paletteID): self?.setColor(paletteID)
            case .openAIPanel: router.route(.openAIPanel(context: id))
            case .closeWindow: router.route(.closeNoteWindow(id))
            case .moveToTrash: self?.coordinator?.moveToTrash(id)
            }
        }
        popUp(menu, from: anchor ?? root.topRow.moreAnchor)
    }

    private func popUpProblemMenu(from anchor: NSView) {
        guard let problem else { return }
        let menu = NoteMenuBuilder(style: environment.style).problemMenu(for: problem) { [weak self] action in
            self?.resolveProblem(action)
        }
        popUp(menu, from: anchor)
    }

    /// 누른 아이콘 바로 아래에 띄운다.
    private func popUp(_ menu: NSMenu, from anchor: NSView) {
        let below = anchor.isFlipped ? anchor.bounds.maxY : anchor.bounds.minY
        let gap = environment.theme.space(.sp1) * (anchor.isFlipped ? 1 : -1)
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.minX, y: below + gap), in: anchor)
    }
}
