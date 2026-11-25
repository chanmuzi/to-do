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
    /// 편집기와 마지막으로 주고받은 본문: 마지막으로 `editor.text`에 넣은 값 또는 `onTextChange`로 받은 값.
    /// 저장소의 본문이 이것과 다를 때만 편집기에 넣는다(`NoteBodyEditing`의 약속).
    var exchangedBody: String
    /// 파일이 없어져 저장소가 받지 못한 변경이 `note`에만 들어 있다.
    var hasUnstoredEdits = false
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
    /// 이 창을 열 때의 여섯 줄 높이. 다음에 열 때 새 글자 설정으로 다시 계산한다.
    let defaultHeightAtOpen: CGFloat
    /// 노트별로 기억하는 높이. 화면에 맞춰 줄인 표시 높이와 별도로 보관한다.
    var manualHeight: CGFloat?
    /// 가장자리를 끄는 중에 높이가 바뀌었다.
    var isDraggingHeight = false
    /// 이 컨트롤러가 마지막으로 알고 있는 창 높이. 이와 다른 높이로 바뀌었으면 앱 밖(창 크기 조절 명령 등)에서 바꾼 것이다.
    var knownHeight: CGFloat?
    /// 내용 높이를 따라 이 컨트롤러가 높이를 바꾸는 중이다.
    var isSettingHeight = false
    /// 높이가 움직이는 중이면 그 목표.
    var heightTarget: CGFloat?
    var heightAnimation: Task<Void, Never>?
    private var heightChangedDuringLayout = false

    private var reminderRefresh: Task<Void, Never>?

    init(note: Note, frame: CGRect, state: NoteWindowState, environment: NotePanelEnvironment) {
        self.noteID = note.id
        self.note = note
        self.exchangedBody = note.body
        self.isPinned = state.isPinned
        manualHeight = state.heightPreference.points
        defaultHeightAtOpen = environment.sizePolicy.defaultHeight
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
        disconnect()
    }

    /// 뷰와 편집기가 이 창으로 보내는 알림을 끊는다. 편집기는 이 창보다 오래 살 수 있고(App이 들고 있다),
    /// 창이 없어지는 도중에도 알린다(텍스트 뷰가 창에서 빠지며 높이를 다시 잰다). 없어진 창으로 알림이 오면 안 된다.
    /// 아직 알리지 않은 글은 창을 내리는 쪽이 먼저 받는다(`flushPendingEdits()`).
    private func disconnect() {
        editor.onTextChange = nil
        editor.onContentHeightChange = nil
        (editor as? any NoteBodyFormatting)?.onFormattingChange = nil
        root.cornerButtons.onFormat = nil
        panel.onResponderChange = nil
        panel.onMouseDown = nil
        panel.onButtonPress = nil
        root.onHoverChange = nil
        root.onLayout = nil
    }

    var isHovered: Bool { hoverOverride ?? isPointerInside }

    var reminderAnchor: NSView { root.topRow.reminderAnchor }

    var snapshot: NoteWindowSnapshot {
        NoteWindowSnapshot(
            noteID: noteID, frame: panel.frame, isPinned: isPinned, level: panel.level.rawValue,
            isVisible: panel.isVisible, isKey: panel.isKeyWindow, isHovered: isHovered,
            windowNumber: panel.windowNumber, problem: problem.map { "\($0)" }
        )
    }

    // MARK: - 띄우고 내리기

    /// 창을 맨 앞에 띄운다. 앱을 앞으로 가져오지 않는다.
    func show(focus: Bool) {
        orderFront()
        if !isShown {
            isShown = true
            knownHeight = panel.frame.height
            environment.recorder.recordOpened(noteID, frame: panel.frame, isPinned: isPinned)
        }
        environment.recorder.recordFronted(noteID)
        if focus { focusBody() }
    }

    func saveReadingPosition() {
        guard let text = editor.view as? NSTextView, let scroll = text.enclosingScrollView else { return }
        let selection = text.selectedRange()
        guard selection.location != NSNotFound else { return }
        environment.recorder.recordReadingPosition(.init(selection: selection, scrollY: scroll.documentVisibleRect.minY), for: noteID)
    }

    func restoreReadingPosition(_ position: NoteWindowState.ReadingPosition?) {
        guard let position, let text = editor.view as? NSTextView, let scroll = text.enclosingScrollView else { return }
        root.layoutSubtreeIfNeeded()
        let source = text.string as NSString
        let start = min(max(0, position.selection.location), source.length)
        var end = start + min(max(0, position.selection.length), source.length - start)
        if end < source.length { end = source.rangeOfComposedCharacterSequence(at: end).location }
        text.setSelectedRange(NSRange(location: end, length: 0))
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin.y = position.scrollY.isFinite ? position.scrollY : 0
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }

    func focusBody() {
        panel.becomeKeyByRequest()
        editor.focus()
    }

    /// 키 창이 된다(키 창이던 노트가 내려갔거나, 사용자가 앱을 앞으로 가져왔다). 제목을 고치던 중이 아니면
    /// 본문이 입력을 받는다. 커서 자리는 그대로다.
    func takeKey() {
        panel.becomeKeyByRequest()
        if !root.topRow.isEditingTitle { editor.focus() }
    }

    /// 제목을 그 자리에서 고치기 시작한다(단축키로).
    func beginTitleEditing() {
        panel.becomeKeyByRequest()
        root.topRow.beginTitleEditing()
    }

    /// "노트 모두 숨기기"(spec 4.3). 되돌릴 때는 겹친 차례를 바꾸지 않는다(부르는 쪽이 뒤에 있던 것부터 부른다).
    func setHidden(_ hidden: Bool) {
        if hidden {
            panel.orderOut(nil)
        } else {
            orderFront()
        }
    }

    /// 창을 보이게 한다. 창이 뜬 직후에는 마우스가 들어왔다는 알림이 오지 않으므로 호버를 다시 잰다.
    private func orderFront() {
        panel.orderFrontRegardless()
        isPointerInside = root.containsPointer
        refreshChrome(animated: false)
        root.syncButtonHover()
    }

    /// 창을 없앤다. 상태를 남기는 일은 부르는 쪽이 한다.
    func discardWindow() {
        reminderRefresh?.cancel()
        heightAnimation?.cancel()
        isShown = false
        disconnect()
        panel.delegate = nil
        panel.close()
    }

    // MARK: - 상단 줄

    func refreshChrome(animated: Bool) {
        refreshScheduleMarkers()
        let state = TopRowState(
            note: note,
            isPinned: isPinned,
            isHovered: isHovered,
            isEditingTitle: root.topRow.isEditingTitle,
            problem: problem,
            options: environment.options(),
            now: Date(),
            calendar: .current
        )
        root.topRow.allowsAgent = environment.options().showsNoteAgent
        root.topRow.agentState = environment.agentFace(note.id)
        root.topRow.apply(state, animated: animated)
        root.topRow.underlineMarkedText = environment.options().underlineMarkedText
        if let textView = editor.view as? NSTextView {
            TextInputPolicy.applyNoteStyle(to: textView, theme: environment.theme, underline: environment.options().underlineMarkedText)
        }
        refreshFormatBar(animated: animated)
        editor.setNotePalette(note.colorID?.rawValue)
        root.background.setPalette(note.colorID?.rawValue, animated: animated)
        panel.title = state.title
        scheduleReminderRefresh()
    }

    private func refreshScheduleMarkers() {
        (editor as? any ScheduleLineDisplaying)?.setScheduleMarkers(
            ScheduleLineMarker.markers(in: note, now: Date(), options: environment.options(), calendar: .current)
        )
    }

    func refreshFormatBar(animated: Bool = false, focusChanged: Bool = false) {
        let formatting = editor as? any NoteBodyFormatting
        let mode = environment.options().formatBar
        root.cornerButtons.isHidden = mode == .hidden
        let visible = formatting != nil && (mode == .always || (mode == .editing && formatting?.isEditingBody == true))
        let changed = visible != root.cornerButtons.showsFormats
        root.cornerButtons.apply(visible: visible, active: visible ? formatting?.activeFormats ?? [] : [])
        root.setHoverControlsAlpha(visible ? 1 : 0, animated: animated)
        if changed { root.layoutFormatBar(preservingScroll: focusChanged) }
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
        let next = note.schedules.filter { $0.isUpcoming(at: now) }.compactMap {
            ReminderPresentation.nextRefresh(item: $0, now: now, options: environment.options(), calendar: .current)
        }.min()
        guard let next else { return }
        let delay = next.timeIntervalSince(now)
        reminderRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshChrome(animated: true)
        }
    }

    // MARK: - 동작

    private func connect() {
        if let formatting = editor as? any NoteBodyFormatting {
            formatting.onFormattingChange = { [weak self] in self?.refreshFormatBar() }
            root.cornerButtons.onFormat = { [weak formatting] in formatting?.applyFormat($0) }
        }
        panel.onResponderChange = { [weak self] in self?.refreshFormatBar(focusChanged: true) }
        panel.onMouseDown = { [unowned self] in coordinator?.endTrashUndo() }
        root.onHoverChange = { [unowned self] inside in
            guard isPointerInside != inside else { return }
            isPointerInside = inside
            refreshChrome(animated: true)
            if inside { root.syncButtonHover() }
        }
        panel.onButtonPress = { [unowned self] in coordinator?.noteButtonPressed() }
        editor.setTitleFocusAction { [weak self] in self?.root.topRow.beginTitleEditing() }
        editor.onTextChange = { [unowned self] text in
            exchangedBody = text
            mutate(deferred: true) { $0.body = text }
            refreshScheduleMarkers()
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

        root.topRow.recognizesDates = coordinator?.recognizesDates ?? true
        root.topRow.onAcceptDate = { [weak self] request in
            guard let self, let accept = coordinator?.onAcceptTitleDate else { throw CocoaError(.featureUnsupported) }
            return try accept(noteID, request)
        }
        root.topRow.onDateError = { [weak self] error in self?.environment.log("제목 예정 저장 실패: \(error)") }
        let router = environment.router
        let id = noteID
        root.topRow.actions = TopRowView.Actions(
            agent: { router.route(.openAgentWindow(id)) },
            more: { [unowned self] anchor in popUpMoreMenu(from: anchor) },
            reminder: { router.route(.openReminderEditor(id)) },
            pin: { [unowned self] in setPinned(!isPinned) },
            problem: { [unowned self] anchor in
                if problem != nil { popUpProblemMenu(from: anchor) }
                else { router.route(.openReminderEditor(id)) }
            },
            titleChanged: { [unowned self] title in mutate(deferred: true) { $0.title = title } },
            titleEditingChanged: { [unowned self] _ in refreshChrome(animated: true) },
            titleReturned: { [unowned self] in editor.focus() }
        )
        root.topRow.closeButton.onPress = { router.route(.closeNoteWindow(id)) }
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
        popUp(makeMoreMenu(), from: anchor ?? root.topRow.moreAnchor)
    }

    func makeMoreMenu() -> NSMenu {
        let router = environment.router
        let id = noteID
        let menu = NoteMenuBuilder(style: environment.style).moreMenu(
            isPinned: isPinned, isArchived: note.isArchived, showsFormatBar: environment.options().formatBar != .hidden,
            selectedPaletteID: note.colorID?.rawValue,
            isAvailable: { action in
                switch action {
                case .setReminder: note.schedules.contains { !$0.isDeleted && !$0.isCompleted } && router.isConnected(.openReminderEditor(id))
                case .moveToSpace: router.isConnected(.openSpacePicker(id))
                case .toggleFormatBar: coordinator?.toggleFormatBar != nil
                case .newNote: true
                case .openLibrary: router.isConnected(.openLibrary)
                case .findNote: router.isConnected(.openBrowse(anchor: id))
                case .toggleArchive, .togglePin, .setColor, .closeWindow, .moveToTrash: true
                }
            }
        ) { [weak self] action in
            switch action {
            case .setReminder: router.route(.openReminderEditor(id))
            case .moveToSpace: router.route(.openSpacePicker(id))
            case .togglePin: self?.setPinned(self?.isPinned == false)
            case .toggleFormatBar: self?.coordinator?.toggleFormatBar?()
            case .setColor(let paletteID): self?.setColor(paletteID)
            case .openLibrary: router.route(.openLibrary)
            case .findNote: router.route(.openBrowse(anchor: id))
            case .newNote: router.route(.newNote(NewNoteRequest(draft: NoteDraft(spaceID: self?.note.spaceID), nextTo: id)))
            case .closeWindow: router.route(.closeNoteWindow(id))
            case .toggleArchive: self?.mutate(deferred: false) { $0.isArchived.toggle() }
            case .moveToTrash: self?.coordinator?.moveToTrash(id)
            }
        }
        return menu
    }

    func problemMenuForVerification() -> NSMenu {
        setProblem(.conflict)
        return NoteMenuBuilder(style: environment.style).problemMenu(for: .conflict) { _ in }
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
